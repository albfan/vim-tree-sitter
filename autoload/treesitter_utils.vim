
function! treesitter_utils#find_tree_buffer() abort
  " Search for buffer with filetype=tree or name=[Tree]
  for bufnr in range(1, bufnr('$'))
    if bufexists(bufnr)
      if getbufvar(bufnr, '&filetype') == 'tree'
        return bufnr
      endif
      if bufname(bufnr) =~ '\[Tree\]'
        return bufnr
      endif
    endif
  endfor
  return -1
endfunction

