" Vars:
let s:NOT_FOUND       = -1
let s:vim_tab_options = {
      \ '&tabline':     '%!choosewin#tabline()',
      \ '&guitablabel': '%{choosewin#get_tablabel(v:lnum)}',
      \ }

" Util::
let s:_ = choosewin#util#get()

" Main:
let s:cw = {}

function! s:cw.start(wins, ...) "{{{1
  let self.conf  = extend(choosewin#config#get(), get(a:000, 0, {}))
  let self.color = choosewin#color#get()

  " Elminate non-exsiting window.
  let self.wins = filter(a:wins, 'index(self.win_all(), v:val) isnot -1')

  try
    " Some status bar plugin need to know if choosewin active or not.
    let g:choosewin_active = 1

    call self.setup()
    call self.first_path()
    if self.conf['tabline_replace']
      let self.tab_options = s:_.buffer_options_set(bufnr(''), s:vim_tab_options)
    endif
    call self.choose()
  catch
    let self.exception = v:exception
  finally
    if self.conf['tabline_replace'] && !empty(self.tab_options)
      call s:_.buffer_options_set(bufnr(''), self.tab_options)
    endif
    call self.finish()
    let g:choosewin_active = 0
    return self.status()
  endtry
endfunction

function! s:cw.setup() "{{{1
  let self.exception   = ''
  let self.win_dest    = ''
  let self.tab_options = {}
  let self.env         = {
        \ 'win_cur': winnr(),
        \ 'win_all': self.win_all(),
        \ 'tab_cur': tabpagenr(),
        \ 'tab_all': self.tab_all(),
        \ 'buf_cur': bufnr(''),
        \ }
  
  let self.env_orig  = deepcopy(self.env)
  let self.label2tab = s:_.dict_create(self.conf['tablabel'], self.env.tab_all)
  let self.tab2label = s:_.dict_create(self.env.tab_all, self.conf['tablabel'])

  if !has_key(self, 'previous')
    let self.previous = []
  endif

  if self.conf['overlay_enable']
    let self.overlay = choosewin#overlay#get()
  endif
endfunction

function! s:cw.statusline_replace() "{{{1
  for winnr in self.wins
    let wv = {}
    let wv.options = s:_.window_options_set( winnr,
          \ { '&statusline': self.prepare_label(winnr, self.conf['label_align']) })
    call setwinvar(winnr, 'choosewin', wv)
  endfor
endfunction

function! s:cw.statusline_restore() "{{{1
  for winnr in self.wins
    let wv = remove(getwinvar(winnr, ''), 'choosewin')
    call s:_.window_options_set(winnr, wv.options)
  endfor
endfunction

function! s:cw.prepare_label(win, align) "{{{1
  let pad   = repeat(' ', self.conf['label_padding'])
  let label = self.win2label[a:win]
  let win_s = pad . label . pad
  let color = winnr() ==# a:win
        \ ? self.color.LabelCurrent
        \ : self.color.Label

  if a:align is 'left'
    return printf('%%#%s# %s %%#%s# %%= ', color, win_s, self.color.Other)
  endif

  if a:align is 'right'
    return printf('%%#%s# %%= %%#%s# %s ', self.color.Other, color, win_s)
  endif

  if a:align is 'center'
    let padding = repeat(' ', winwidth(a:win)/2-len(win_s))
    return printf('%%#%s# %s %%#%s# %s %%#%s# %%= ',
          \ self.color.Other, padding, color, win_s, self.color.Other)
  endif
endfunction

function! s:cw.tab_choose(num) "{{{1
  silent execute 'tabnext ' a:num
  let self.env.tab_cur = a:num
endfunction

function! s:cw.win_choose(num) "{{{1
  if !self.conf['noop']
    silent execute a:num 'wincmd w'
  endif
  let self.env.win_cur = a:num
endfunction

function! s:cw.choose() "{{{1
  while 1
    call self.label_show()
    let  input = self.read_input()
    call self.label_clear()

    " Tab label is chosen.
    let num = s:_.get_ic(self.label2tab, input)
    if !empty(num)
      call self.do_tab(num)
      continue
    endif

    " Win label is chosen.
    let num = s:_.get_ic(self.label2win, input)
    if !empty(num)
      call self.do_win(num)
    endif

    let action = get(self.conf['keymap'], input, 'cancel')
    let action_func = 'do_' . action
    if !s:_.is_Funcref(get(self, action_func))
      throw 'UNKNOWN_ACTION'
    endif
    call self[action_func]()
  endwhile
endfunction
"}}}

" Action:
function! s:cw.do_win(num) "{{{1
  let self.win_dest = a:num
  throw 'CHOSE'
endfunction

function! s:cw.do_tab(num) "{{{1
  call self.tab_choose(a:num)
  let self.wins = self.win_all()
endfunction

function! s:cw.do_tab_first() "{{{1
  call self.do_tab(1)
endfunction

function! s:cw.do_tab_prev() "{{{1
  call self.do_tab(max([1, self.env.tab_cur - 1]))
endfunction

function! s:cw.do_tab_next() "{{{1
  call self.do_tab(min([tabpagenr('$'), self.env.tab_cur + 1]))
endfunction

function! s:cw.do_tab_last() "{{{1
  call self.do_tab(tabpagenr('$'))
endfunction

function! s:cw.do_tab_close() "{{{1
  silent! tabclose
  call self.do_tab(tabpagenr())
endfunction

function! s:cw.do_win_land() "{{{1
  let self.win_dest = winnr()
  throw 'CHOSE'
endfunction

function! s:cw.do_previous() "{{{1
  if empty(self.previous)
    throw 'NO_PREVIOUS_WINDOW'
  endif

  let [ tab_dst, self.win_dest ] = self.previous
  call self.tab_choose(tab_dst)
  throw 'CHOSE'
endfunction

function! s:cw.do_swap() "{{{1
  if self.conf['swap']
    call self.do_previous()
  else
    let self.conf['swap'] = 1
  endif
endfunction

function! s:cw.do_swap_stay() "{{{1
  if self.conf['swap']
    call self.do_previous()
  else
    let self.conf['swap'] = 1
    if !has_key(self.conf, 'swap_stay')
      let self.conf['swap_stay'] = action ==# 'swap_stay'
    endif
    let self.wins = self.win_all()
    call self.label_show()
    return
  endif
endfunction

function! s:cw.do_cancel()
  call self.tab_choose(self.env_orig.tab_cur)
  call self.win_choose(self.env_orig.win_cur)
  throw 'CANCELED'
endfunction
"}}}

function! s:cw.call_hook(hook_point, arg) "{{{1
  if !self.conf['hook_enable']
        \ || index(self.conf['hook_bypass'], a:hook_point ) !=# -1
    return a:arg
  endif
  let HOOK = get(self.conf['hook'], a:hook_point, 0)
  if s:_.is_Funcref(HOOK)
    return call(HOOK, [a:arg])
  else
    return a:arg
  endif
endfunction

function! s:cw.label_show() "{{{1
  try
    let wins_save     = self.wins
    let wins_filtered = self.call_hook('filter_window', self.wins)
    let self.wins     = wins_filtered
  catch
    let self.wins = wins_save
  endtry

  let self.label2win = s:_.dict_create(self.conf.label, self.wins)
  let self.win2label = s:_.dict_create(self.wins, self.conf.label)

  if self.conf['statusline_replace']
    call self.statusline_replace()
  endif
  if self.conf['overlay_enable']
    call self.overlay.start(self.wins, self.conf)
  endif
  redraw
endfunction

function! s:cw.label_clear() "{{{1
  if self.conf['statusline_replace']
    call self.statusline_restore()
  endif
  if self.conf['overlay_enable']
    call self.overlay.restore()
  endif
endfunction

function! s:cw.first_path() "{{{1
  if empty(self.wins)
    throw 'RETURN'
  endif
  if len(self.wins) is 1
    if self.conf['auto_choose']
      let self.win_dest = self.wins[0]
      throw 'CHOSE'
    elseif self.conf['return_on_single_win']
      throw 'RETURN'
    endif
  endif
endfunction
"}}}

" Tabline:
function! s:cw.tabline() "{{{1
  let R   = ''
  let pad = repeat(' ', self.conf['label_padding'])
  let sepalator = printf('%%#%s# ', self.color.Other)
  let tab_all = self.tab_all()
  for tabnum in tab_all
    let color = self.color[ tabpagenr() is tabnum ? "LabelCurrent" : "Label" ]
    let R .= printf('%%#%s# %s ', color,  pad . self.get_tablabel(tabnum) . pad)
    let R .= tabnum isnot tab_all[-1] ? sepalator : ''
  endfor
  let R .= printf('%%#%s#', self.color.Other)
  return R
endfunction

function! s:cw.get_tablabel(num) "{{{1
  return len(self.conf['tablabel']) > a:num
        \ ? self.conf['tablabel'][a:num-1]
        \ : '..'
endfunction
"}}}

" Misc:
function! s:cw.read_input() "{{{1
  redraw
  let prompt = ( self.conf['swap'] ? '[swap] ' : '' ) . 'chooose > '
  echohl PreProc
  echon prompt
  echohl Normal
  return nr2char(getchar())
endfunction

function! s:cw.blink_cword() "{{{1
  if ! self.conf['blink_on_land']
    return
  endif
  for i in range(2)
    let id = matchadd(self.color.Land, s:cword_pattern)
    redraw
    sleep 80m
    call matchdelete(id)
    redraw 
    sleep 80m
  endfor
endfunction
let s:cword_pattern = '\k*\%#\k*'

function! s:cw.win_all() "{{{1
  return range(1, winnr('$'))
endfunction

function! s:cw.tab_all() "{{{1
  return range(1, tabpagenr('$'))
endfunction

function! s:cw.status() "{{{1
  if empty(self.exception)
    return
  endif
  if self.exception =~# 'CANCELED\|RETURN'
    return []
  else
    return [ self.env.tab_cur, self.env.win_cur ]
  endif
endfunction

function! s:cw.message() "{{{1
  if !empty(self.exception)
    echohl Type
    echon 'choosewin: '
    echohl Normal
  endif
  echon self.exception
endfunction
"}}}

" Restore:
function! s:cw.finish() "{{{1
  echo '' | redraw
  if self.conf['noop'] && self.env.tab_cur !=# self.env_orig.tab_cur
    silent execute 'tabnext ' self.env_orig.tab_cur
  endif
  if !empty(self.win_dest)
    call self.win_choose(self.win_dest)

    if self.conf['noop']
      return
    endif

    if self.conf['swap']
      let buf_dst = winbufnr('')
      execute 'hide buffer' self.env_orig.buf_cur
      silent execute 'tabnext ' self.env_orig.tab_cur
      silent execute self.env_orig.win_cur 'wincmd w'
      execute 'hide buffer' buf_dst

      if self.conf['swap_stay']
        let self.previous = [ self.env.tab_cur, self.env.win_cur ]
      else
        silent execute 'tabnext ' self.env.tab_cur
        silent execute self.env.win_cur 'wincmd w'
        let self.previous = [ self.env_orig.tab_cur, self.env_orig.win_cur ]
      endif
    else
      let self.previous = [ self.env_orig.tab_cur, self.env_orig.win_cur ]
    endif
  endif
  call self.blink_cword()
  if !self.exception =~# 'CHOSE\|RETURN'
    call self.message()
  endif
endfunction
"}}}

" API:
function! choosewin#start(...) "{{{1
  return call(s:cw.start, a:000, s:cw)
endfunction

function! choosewin#tabline() "{{{1
  return s:cw.tabline()
endfunction

function! choosewin#get_tablabel(num) "{{{1
  return s:cw.get_tablabel(a:num)
endfunction

" function! choosewin#get_previous() "{{{1
  " return s:cw.previous
" endfunction
"}}}

if expand("%:p") !=# expand("<sfile>:p")
  finish
endif

" vim: foldmethod=marker
