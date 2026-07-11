" Open local C++ Markdown references in a right-side split.
" Configure with:
"   let g:cppref_root = '/path/to/cpp/reference/md'
" or:
"   export CPPREF_ROOT=/path/to/cpp/reference/md
" Default keymap for C/C++ buffers:
"   <Leader>k

if exists('g:loaded_cppref')
  finish
endif
let g:loaded_cppref = 1

let s:default_split_width = get(g:, 'cppref_split_width', 82)
let s:use_glow = get(g:, 'cppref_use_glow', 1)
let s:focus_ref = get(g:, 'cppref_focus', 0)

function! s:ReferenceRoot() abort
  if exists('g:cppref_root') && !empty(g:cppref_root)
    return expand(g:cppref_root)
  endif

  if !empty($CPPREF_ROOT)
    return expand($CPPREF_ROOT)
  endif

  return ''
endfunction

function! s:NormalizeTerm(term) abort
  let l:term = trim(a:term)
  let l:term = substitute(l:term, '^std::', '', '')
  return l:term
endfunction

function! s:ScoreFile(file, term) abort
  let l:name = tolower(fnamemodify(a:file, ':t:r'))
  let l:term = tolower(a:term)
  let l:safe = tolower(substitute(a:term, '[^A-Za-z0-9_+-]', '_', 'g'))

  if l:name ==# l:term || l:name ==# l:safe
    return 0
  endif

  if l:name =~# '\V' . escape(l:term, '\')
    return 1
  endif

  if l:safe !=# l:term && l:name =~# '\V' . escape(l:safe, '\')
    return 2
  endif

  return 9
endfunction

function! s:FindReferences(term) abort
  let l:root = s:ReferenceRoot()
  if empty(l:root)
    echohl ErrorMsg
    echom 'CppRef: set g:cppref_root or CPPREF_ROOT'
    echohl None
    return []
  endif

  if !isdirectory(l:root)
    echohl ErrorMsg
    echom 'CppRef: reference root not found: ' . l:root
    echohl None
    return []
  endif

  let l:term = s:NormalizeTerm(a:term)
  if empty(l:term)
    echohl ErrorMsg
    echom 'CppRef: no search term'
    echohl None
    return []
  endif

  let l:files = globpath(l:root, '**/*.md', 0, 1)
  let l:matches = []

  for l:file in l:files
    let l:score = s:ScoreFile(l:file, l:term)
    if l:score < 9
      call add(l:matches, [l:score, l:file])
    endif
  endfor

  if empty(l:matches)
    echohl WarningMsg
    echom 'CppRef: no markdown reference found for: ' . l:term
    echohl None
    return []
  endif

  call sort(l:matches)
  return l:matches
endfunction

function! s:ApplyReferenceView() abort
  setlocal filetype=markdown
  setlocal readonly nomodifiable noswapfile
  setlocal nobuflisted
  setlocal wrap linebreak breakindent
  setlocal nolist
  setlocal nonumber norelativenumber
  setlocal signcolumn=no
  setlocal foldcolumn=0
  setlocal colorcolumn=
  setlocal nocursorline
  setlocal winfixwidth

  if exists('+conceallevel')
    setlocal conceallevel=2
  endif

  nnoremap <silent> <buffer> q :close!<CR>
  nnoremap <silent> <buffer> <Esc> :close!<CR>
endfunction

function! s:ApplyPreviewView() abort
  setlocal nobuflisted noswapfile
  setlocal nonumber norelativenumber
  setlocal signcolumn=no
  setlocal foldcolumn=0
  setlocal nolist
  setlocal winfixwidth
  setlocal nocursorline

  nnoremap <silent> <buffer> q :close!<CR>
  nnoremap <silent> <buffer> <Esc> :close!<CR>
  tnoremap <silent> <buffer> q <C-\><C-n>:close!<CR>
  tnoremap <silent> <buffer> <Esc> <C-\><C-n>:close!<CR>
endfunction

function! s:OpenReferenceFile(file, source_winid) abort
  if empty(a:file)
    return
  endif

  let l:current = a:source_winid
  call win_gotoid(l:current)
  execute 'rightbelow vertical ' . s:default_split_width . 'new'
  execute 'vertical resize ' . s:default_split_width

  if s:use_glow && executable('glow') && exists('*term_start')
    let l:preview_width = max([40, winwidth(0) - 4])
    call term_start(['glow', '-p', '-w', string(l:preview_width), a:file], {
          \ 'curwin': 1,
          \ 'term_name': 'cppref-preview',
          \ })
    call s:ApplyPreviewView()
    stopinsert
  else
    execute 'edit ' . fnameescape(a:file)
    call s:ApplyReferenceView()
  endif

  if !s:focus_ref
    call win_gotoid(l:current)
  endif
endfunction

function! s:OpenSelectedReference(source_winid, line) abort
  let l:columns = split(a:line, "\t")
  if len(l:columns) < 2
    return
  endif

  call s:OpenReferenceFile(l:columns[-1], a:source_winid)
endfunction

function! s:SelectReference(matches, source_winid) abort
  let l:root = s:ReferenceRoot()
  let l:items = []

  for l:match in a:matches
    let l:file = l:match[1]
    let l:relative = substitute(l:file, '^' . escape(l:root . '/', '\'), '', '')
    call add(l:items, l:relative . "\t" . l:file)
  endfor

  if exists('*fzf#run')
    call fzf#run(fzf#wrap({
          \ 'source': l:items,
          \ 'sink': function('s:OpenSelectedReference', [a:source_winid]),
          \ 'options': [
          \   '--prompt=CppRef> ',
          \   '--delimiter=\t',
          \   '--with-nth=1',
          \ ],
          \ }))
    return
  endif

  echohl WarningMsg
  echom 'CppRef: multiple references found; install/load fzf.vim to choose. Opening first match.'
  echohl None
  call s:OpenReferenceFile(a:matches[0][1], a:source_winid)
endfunction

function! s:OpenReference(...) abort
  let l:term = a:0 > 0 && !empty(a:1) ? a:1 : expand('<cword>')
  let l:matches = s:FindReferences(l:term)
  if empty(l:matches)
    return
  endif

  let l:current = win_getid()
  if len(l:matches) == 1
    call s:OpenReferenceFile(l:matches[0][1], l:current)
    return
  endif

  call s:SelectReference(l:matches, l:current)
endfunction

command! -nargs=? -complete=file CppRef call s:OpenReference(<q-args>)

augroup cppref_keymap
  autocmd!
  autocmd FileType c,cpp nnoremap <silent> <buffer> <Leader>k :CppRef<CR>
augroup END
