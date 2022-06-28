command! -bar Luadev lua require'luadev'.start()

noremap <silent>  <Plug>(Luadev-RunLine) :<c-u>call <SID>luadev_run_line("lua")<cr>
vnoremap <silent> <Plug>(Luadev-Run) :<c-u>call <SID>luadev_run_operator(v:true, "lua")<cr>
nnoremap <silent> <Plug>(Luadev-Run) :<c-u>set opfunc=<SID>luadev_run_operator<cr>g@
noremap <silent> <Plug>(Luadev-RunWord) :<c-u>call luaeval("require'luadev'.exec(_A)", <SID>get_current_word())<cr>
inoremap <Plug>(Luadev-Complete) <Cmd>lua require'luadev.complete'()<cr>

noremap <silent> <Plug>(Luadev-RunVimLine) :<c-u> call <SID>luadev_run_line("vim")<cr>
vnoremap <silent> <Plug>(Luadev-RunVim) :<c-u>call <SID>luadev_run_operator(v:true, "vim")<cr>

function! s:luadev_run_line(ext)

  let line = getline(".")

  if expand("%") == "[nvim-lua]"
    if line !~ '^\d\+>'
      delete
    else
    endif
  endif

  call v:lua.require'luadev'.exec(line, a:ext)
endfunction

" thanks to @xolox on stackoverflow
function! s:luadev_run_operator(is_op, ext = 'lua')
    let [lnum1, col1] = getpos(a:is_op ? "'<" : "'[")[1:2]
    let [lnum2, col2] = getpos(a:is_op ? "'>" : "']")[1:2]

    if lnum1 > lnum2
      let [lnum1, col1, lnum2, col2] = [lnum2, col2, lnum1, col1]
    endif

    let lines = getline(lnum1, lnum2)
    if  a:is_op == v:true || lnum1 == lnum2
      let lines[-1] = lines[-1][: col2 - (&selection == 'inclusive' ? 1 : 2)]
      let lines[0] = lines[0][col1 - 1:]
      if expand("%") == "[nvim-lua]" && lines[0] !~ '^\d\+>'
        execute lnum1 ";" lnum2 "delete"
      endif
    endif
    let lines =  join(lines, "\n")
    call v:lua.require'luadev'.exec(lines, a:ext)
endfunction


function! s:get_current_word()
    let isk_save = &isk
    let &isk = '@,48-57,_,192-255,.'
    let word = expand("<cword>")
    let &isk = isk_save
    return word
endfunction
