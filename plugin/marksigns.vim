" ========================================================================///
" Description: uncomplicated alternative to vim-signature
" Author:      Gianmaria Bajo ( mg1979@git.gmail.com )
" File:        marksigns.vim
" License:     MIT
" Created:     mer 09 ottobre 2019 21:57:54
" Modified:    lun 13 luglio 2020 12:17:50
" ========================================================================///

" Purpose: to show lower/uppercase marks in the signs column, and only those.
" No 'markers', no viminfo interferences.
" To go to next/previous mark you can use [`, ]` (vim builtins)

" COMMAND     MAPPINGS  DESCRIPTION
"------------------------------------------------------------------------------
" Mark:        m,  dm   add a mark, or delete it (BANG)
" Marks:       m<Tab>   list lowercase letter marks
"                       with <count>, display also numeric
"              m<S-Tab> list uppercase letter marks
"                       with <count>, display also numeric
"              m?       list all alphanumeric marks
" Marksigns:            toggle the signs visibility, or force disable (BANG)

" Option:               g:marksigns_enable_at_start (default 1)
"------------------------------------------------------------------------------

" GUARD {{{1
if !has('signs') || !has('timers') || exists('g:loaded_marksigns')
  finish
endif
let g:loaded_marksigns = 1

let s:enabled = get(g:, 'marksigns_enable_at_start', 1)
let s:write_shada = 0


" Preserve external compatibility options, then enable full vim compatibility
let s:save_cpo = &cpo
set cpo&vim

" COMMANDS AND MAPPINGS {{{1
augroup marksigns
  au!
  au TextChanged,InsertLeave * call s:update_buffer(1)
  au BufEnter *                let s:ready = 1 | call s:update_buffer(0)
  au SessionLoadPost *         call s:update_buffer(0)
  au ColorScheme *             call s:higroup()
  au VimLeave *                call s:wshada()
augroup END

command! -bang -nargs=? Mark      call s:add_or_delete_mark(<bang>0, <q-args>)
command! -nargs=?       Marks     call s:list_marks(<q-args>)
command! -bang          Marksigns call s:toggle(<bang>0)

if get(g:, 'marksigns_mappings', 1)
  nnoremap <silent> m        :Mark<cr>
  nnoremap <silent> dm       :Mark!<cr>
  nnoremap <silent> m<tab>   :<c-u>Marks <C-r>=v:count?"0a":"a"<CR><cr>
  nnoremap <silent> m<s-tab> :<c-u>Marks <C-r>=v:count?"0A":"A"<CR><cr>
  nnoremap <silent> m?       :<c-u>Marks<cr>
endif

if get(g:, 'marksigns_plugs', 0)
  nnoremap <silent> <Plug>(Mark)          :Mark<cr>
  nnoremap <silent> <Plug>(MarkDelete)    :Mark!<cr>
  nnoremap <silent> <Plug>(MarksLocal)    :<c-u>Marks <C-r>=v:count<CR> a<cr>
  nnoremap <silent> <Plug>(MarksGlobal)   :<c-u>Marks <C-r>=v:count<CR> A<cr>
  nnoremap <silent> <Plug>(MarksAll)      :<c-u>Marks <C-r>=v:count<CR><cr>
  nnoremap <silent> <Plug>(MarksNumbered) :<c-u>Marks 1<cr>
endif

"}}}


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Main functions
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

fun! s:update_buffer(postpone) abort
  " Initialize or update buffer. {{{1

  " signs are disabled, unplace them if just deactivated
  if !s:enabled
    return exists('b:mark_signs') ? b:mark_signs.disable() : 0
  endif

  " while a session is loading, skip updates until SessionLoadPost triggers
  if exists('g:SessionLoad') && a:postpone | return | endif

  " If the update is triggered by TextChanged or InsertLeave, start a timer
  " we will come back here after the timer callback
  if a:postpone | return s:start_timer() | endif

  " initialize buffer marks object
  if !exists('b:mark_signs') | let b:mark_signs = copy(s:Signs) | endif

  " set lazyredraw and perform the update
  let oldlz = &lz
  set lz
  call b:mark_signs.update_all()
  let &lz = oldlz

  " reset the timer flag
  let s:ready = 1
endfun "}}}

fun! s:add_or_delete_mark(delete, mark) abort
  " Add or delete mark, updating signs. {{{1
  let mark = a:mark
  if empty(mark)
    let mark = nr2char(getchar())
    if mark == "\<esc>"
      " cancel
      return
    elseif mark !~ '[A-Za-z]'
      " let vim handle the others
      exe (a:delete ? 'delmarks ' : 'normal! m') . mark
      return
    endif
  endif
  if a:delete
    call b:mark_signs.delete_mark(mark)
  else
    call b:mark_signs.add_mark(mark)
  endif
  silent doautocmd <nomodeline> User MarkChanged
endfun "}}}

fun! s:list_marks(arg) abort
  " List numbered or lowercase/uppercase marks. {{{1
  let marks = split(execute('marks'), '\n')
  echohl Title
  echo marks[0]
  echohl None
  let pat = '['
  if a:arg !~ '\S'
    let pat .= 'a-zA-Z0-9'
  else
    if a:arg =~# '[0-9]' | let pat .= '0-9' | endif
    if a:arg =~# '[a-z]' | let pat .= 'a-z' | endif
    if a:arg =~# '[A-Z]' | let pat .= 'A-Z' | endif
  endif
  let pat .= ']'
  for m in sort(filter(marks, 'v:val[1] =~# "' . pat . '"')[1:] + ['> '])
    echo m
  endfor
  let c = nr2char(getchar())
  call feedkeys("\<CR>")
  if index(b:mark_signs.valid, c) >= 0 || c =~ '\d'
    exe "normal! '".c.'zvzz'
  endif
endfun "}}}

fun! s:toggle(force_disable) abort
  " Toggle visibility of mark signs. {{{1
  let s:enabled = a:force_disable ? 0 : !s:enabled
  call s:update_buffer(0)
endfun "}}}

fun! s:update_all_windows() abort
  " Update signs for all windows in current tab. {{{1
  let curwin = winnr()
  for w in range(winnr('$'))
    noautocmd exe (w+1).'wincmd w'
    if exists('b:mark_signs')
      call b:mark_signs.update_all()
    endif
  endfor
  exe curwin . 'wincmd w'
endfun "}}}


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Signs class
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:Signs = {}

"------------------------------------------------------------------------------

" Update functions

fun! s:Signs.update_all() abort
  " Update signs for buffer. {{{1
  let self.marks = get(self, 'marks', {})
  let self.valid = []
  let self.id = get(self, 'id', 60000)

  " parse and iterate all marks
  for m in split(execute('marks'), '\n')[1:]
    let tk = split(m)
    let [ mark, ln, col ] = [ tk[0], tk[1], tk[2] ]

    let [ lcase, ucase ] = [ mark =~# '\l', mark =~# '\u' ]

    " we're only interested in lowercase and uppercase marks
    if !lcase && !ucase | continue | endif
    call add(self.valid, mark)

    " if uppercase mark, check if it's in current file
    let same_file = ucase && split(getline(ln)) ==# tk[3:]

    let mark_has_sign = has_key(self.marks, mark) && has_key(self.marks[mark], 'id')

    if mark_has_sign
      " if mark is already registered and equal, no need to update
      let same_pos = self.marks[mark].ln == tk[1] && self.marks[mark].col == tk[2]
      if lcase && same_pos     | continue | endif
      if same_file && same_pos | continue | endif
      " if not equal, remove previous sign
      call self.remove_sign(mark)
    endif

    " if mark is lowercase, place it anyway, if uppercase, only if in current file
    if lcase
      let self.marks[mark] = {'ln': tk[1], 'col': tk[2]}
      call self.place_sign(mark)
    else
      let self.marks[mark] = {'ln': tk[1], 'col': tk[2]}
      if same_file
        call self.place_sign(mark)
      endif
    endif
  endfor
  call self.purge_invalid()
endfun "}}}

fun! s:Signs.purge_invalid() abort
  " Remove placed signs for invalid marks. {{{1
  for m in keys(self.marks)
    if index(self.valid, m) < 0
      call self.remove_sign(m)
    endif
  endfor
endfun "}}}

fun! s:Signs.disable() abort
  " Remove all signs for the current buffer, if any. {{{1
  for m in keys(self.marks)
    call self.remove_sign(m)
  endfor
endfun "}}}

"------------------------------------------------------------------------------

" Signs functions

fun! s:Signs.place_sign(mark) abort
  " Place sign at line and register it. {{{1
  try
    let line   = 'line='.self.marks[a:mark].ln
    let name   = 'name=mark_'.a:mark
    let buffer = 'buffer='.bufnr('')
    exe 'sign place' self.id line name buffer
    let self.marks[a:mark].id = self.id
    let self.id += 1
  catch /E716:/
    unlet self.marks[a:mark]
  endtry
endfun "}}}

fun! s:Signs.remove_sign(mark) abort
  " Remove the sign and unregister the mark. {{{1
  if has_key(self.marks[a:mark], 'id')
    exe 'sign unplace' self.marks[a:mark].id 'buffer='.bufnr('')
  endif
  unlet self.marks[a:mark]
endfun "}}}

"------------------------------------------------------------------------------

" Marks functions

fun! s:Signs.delete_mark(mark) abort
  " Delete a mark, if assigned. {{{1
  if index(keys(self.marks), a:mark) >= 0
    exe 'silent! delmarks' a:mark
    if a:mark =~ '[A-Z]'
      call s:update_all_windows()
    else
      call self.remove_sign(a:mark)
    endif
    let s:write_shada = has('nvim')
  else
    call s:warn('Mark '.a:mark.' not defined')
  endif
endfun "}}}

fun! s:Signs.add_mark(mark) abort
  " Add a mark, and relative sign. {{{1
  exe 'normal! m' . a:mark
  if a:mark =~ '[A-Z]'
    call s:update_all_windows()
  else
    call self.update_all()
  endif
endfun "}}}



"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Helpers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


fun! s:warn(text) abort
  " Print a warning. {{{1
  echohl WarningMsg
  echo a:text
  echohl None
endfun "}}}

fun! s:higroup() abort
  " Create/restore highlight group for signs. {{{1
  let gui  = has('gui_running') || (has('termguicolors') && &termguicolors)
  let mode = gui ? 'gui' : 'cterm'
  let hi   = synIDattr(synIDtrans(hlID('SignColumn')), 'bg', mode)
  let color = empty(hi) || hi == -1 ? mode.'bg=NONE' : mode.'bg='.hi
  exe 'silent! hi default MarkBar guifg=#ff0000 ctermfg=9' color
endfun "}}}

fun! s:start_timer() abort
  " Start timer: its callback will trigger the update. {{{1
  " if s:ready is false, it means that there's already a timer in progress
  " s:ready will be set to 1 by the callback, or on BufEnter if buffer changes
  if !s:ready | return | endif
  let s:ready = 0
  call timer_start(500, { t -> s:update_buffer(0) })
endfun "}}}

fun! s:wshada() abort
  " Write nvim shada file, so that marks are updated. {{{1
  if s:write_shada
    silent! wshada!
  endif
endfun "}}}

"------------------------------------------------------------------------------

" Initialize highlight and signs {{{1
call s:higroup()
sign define mark_a text=a texthl=MarkBar
sign define mark_b text=b texthl=MarkBar
sign define mark_c text=c texthl=MarkBar
sign define mark_d text=d texthl=MarkBar
sign define mark_e text=e texthl=MarkBar
sign define mark_f text=f texthl=MarkBar
sign define mark_g text=g texthl=MarkBar
sign define mark_h text=h texthl=MarkBar
sign define mark_i text=i texthl=MarkBar
sign define mark_j text=j texthl=MarkBar
sign define mark_k text=k texthl=MarkBar
sign define mark_l text=l texthl=MarkBar
sign define mark_m text=m texthl=MarkBar
sign define mark_n text=n texthl=MarkBar
sign define mark_o text=o texthl=MarkBar
sign define mark_p text=p texthl=MarkBar
sign define mark_q text=q texthl=MarkBar
sign define mark_r text=r texthl=MarkBar
sign define mark_s text=s texthl=MarkBar
sign define mark_t text=t texthl=MarkBar
sign define mark_u text=u texthl=MarkBar
sign define mark_v text=v texthl=MarkBar
sign define mark_w text=w texthl=MarkBar
sign define mark_x text=x texthl=MarkBar
sign define mark_y text=y texthl=MarkBar
sign define mark_z text=z texthl=MarkBar
sign define mark_A text=A texthl=MarkBar
sign define mark_B text=B texthl=MarkBar
sign define mark_C text=C texthl=MarkBar
sign define mark_D text=D texthl=MarkBar
sign define mark_E text=E texthl=MarkBar
sign define mark_F text=F texthl=MarkBar
sign define mark_G text=G texthl=MarkBar
sign define mark_H text=H texthl=MarkBar
sign define mark_I text=I texthl=MarkBar
sign define mark_J text=J texthl=MarkBar
sign define mark_K text=K texthl=MarkBar
sign define mark_L text=L texthl=MarkBar
sign define mark_M text=M texthl=MarkBar
sign define mark_N text=N texthl=MarkBar
sign define mark_O text=O texthl=MarkBar
sign define mark_P text=P texthl=MarkBar
sign define mark_Q text=Q texthl=MarkBar
sign define mark_R text=R texthl=MarkBar
sign define mark_S text=S texthl=MarkBar
sign define mark_T text=T texthl=MarkBar
sign define mark_U text=U texthl=MarkBar
sign define mark_V text=V texthl=MarkBar
sign define mark_W text=W texthl=MarkBar
sign define mark_X text=X texthl=MarkBar
sign define mark_Y text=Y texthl=MarkBar
sign define mark_Z text=Z texthl=MarkBar
"}}}
" Restore previous external compatibility options "{{{1
let &cpo = s:save_cpo
unlet s:save_cpo
"}}}

" vim: et sw=2 ts=2 sts=2 fdm=marker

