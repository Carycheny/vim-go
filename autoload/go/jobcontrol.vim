" s:jobs is a global reference to all jobs started with Spawn() or with the
" internal function s:spawn
let s:jobs = {}

" Spawn is a wrapper around s:spawn. It can be executed by other files and
" scripts if needed.
function! go#jobcontrol#Spawn(args)
  let job = s:spawn(a:args[0], a:args)
  return job.id
endfunction

" spawn spawns a go subcommand with the name and arguments with jobstart. Once
" a job is started a reference will be stored inside s:jobs. spawn changes the
" GOPATH when g:go_autodetect_gopath is enabled. The job is started inside the
" current files folder.
function! s:spawn(name, args)
  let job = { 
        \ 'name': a:name, 
        \ 'stderr' : [],
        \ 'stdout' : [],
        \ 'on_stdout': function('s:on_stdout'),
        \ 'on_stderr': function('s:on_stderr'),
        \ 'on_exit' : function('s:on_exit'),
        \ }

  " modify GOPATH if needed
  let old_gopath = $GOPATH
  let $GOPATH = go#path#Detect()

  " execute go build in the files directory
  let cd = exists('*haslocaldir') && haslocaldir() ? 'lcd ' : 'cd '
  let dir = getcwd()
  try
    execute cd . fnameescape(expand("%:p:h"))

    " append the subcommand, such as 'build'
    let argv = ['go'] + a:args
    " call extend(argv, a:args) 

    " run, forrest, run!
    let id = jobstart(argv, job)
    let job.id = id
    let s:jobs[id] = job
  finally
    execute cd . fnameescape(dir)
  endtry

  " restore back GOPATH
  let $GOPATH = old_gopath
  return job
endfunction

" on_stdout is the stdout handler for jobstart(). It collects the output of
" stderr and stores them to the jobs internal stdout list. 
function! s:on_stdout(job_id, data)
  if !has_key(s:jobs, a:job_id)
    return
  endif
  let job = s:jobs[a:job_id]

  call extend(job.stdout, a:data)
endfunction

" on_stderr is the stderr handler for jobstart(). It collects the output of
" stderr and stores them to the jobs internal stderr list.
function! s:on_stderr(job_id, data)
  if !has_key(s:jobs, a:job_id)
    return
  endif
  let job = s:jobs[a:job_id]

  call extend(job.stderr, a:data)
endfunction

" on_exit is the exit handler for jobstart(). It handles cleaning up the job
" references and also displaying errors in the quickfix window collected by
" on_stderr handler
function! s:on_exit(job_id, data)
  if !has_key(s:jobs, a:job_id)
    return
  endif
  let job = s:jobs[a:job_id]

  if empty(job.stderr)
    call setqflist([])
    call go#util#Cwindow()

    redraws! | echon "vim-go: " | echohl Function | echon printf("[%s] SUCCESS", self.name) | echohl None
    return
  else
    call go#tool#ShowErrors(join(job.stderr, "\n"))
    let errors = getqflist()
    call go#util#Cwindow(len(errors))

    if !empty(errors)
      cc 1 "jump to first error if there is any
    endif

    redraws! | echon "vim-go: " | echohl ErrorMsg | echon printf("[%s] FAILED", self.name)| echohl None
  endif

  " do not keep anything when we are finished
  unlet s:jobs[a:job_id]
endfunction

" abort_all aborts all current jobs created with s:spawn()
function! s:abort_all()
  if empty(s:jobs)
    return
  endif

  for id in keys(s:jobs)
    if id > 0
      silent! call jobstop(id)
    endif
  endfor

  let s:jobs = {}
endfunction

" abort aborts the job with the given name, where name is the first argument
" passed to s:spawn()
function! s:abort(name)
  if empty(s:jobs)
    return
  endif

  for job in values(s:jobs)
    if job.name == name && job.id > 0
      silent! call jobstop(job.id)
      unlet s:jobs['job.id']
      redraws! | echon "vim-go: " | echohl WarningMsg | echon printf("[%s] ABORTED", a:name) | echohl None

    endif
  endfor
endfunction

" vim:ts=2:sw=2:et
