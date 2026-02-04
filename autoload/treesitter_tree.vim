" ------------------------
" Vim Plugin: Tree Representation
" ------------------------

" ------------------------
" Initialize and Render the Tree Buffer
" ------------------------

function! treesitter_tree#show_tree() abort
  " Open the tree buffer
  call s:initialize_tree_buffer()
  call s:render_tree_buffer()
endfunction

function! s:initialize_tree_buffer() abort
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  "setlocal modifiable
  setlocal nowrap
  setlocal foldenable " Enable folding explicitly
  setlocal foldmethod=manual
  setlocal foldcolumn=0
  set filetype=tree
  file [Tree] " Set buffer name for identification

  " Initialize buffer-local variables
  let b:expanded_nodes = [] " Track expanded nodes by their IDs
  let b:line_to_node = {} " Maps buffer line numbers to node IDs
endfunction

function! s:render_tree_buffer() abort
  " Clear the buffer
  let l:save_pos = getpos('.')
  call deletebufline('%', 1, '$')
  let b:line_to_node = {}

  " Recursively render the tree
  let lines = s:render_tree(g:tree_struct, b:expanded_nodes, 0, b:line_to_node, 0)
  call setline(1, lines)
  call setpos('.', l:save_pos)
  "setlocal modifiable
endfunction

function s:get_node(node)
  for node in a:tree
    let node_id = node.id
    let is_parent = has_key(node, 'children') && len(node.children) > 0
    let is_expanded = index(a:expanded_nodes, node_id) >= 0
    let prefix = is_parent ? (is_expanded ? '▾ ' : '▸ ') : '• '
    call add(lines, repeat('  ', a:indent_level) . prefix . node.name)

    " Map the line number to the current node ID
    let line = len(lines) + a:init_line
    let a:line_map[line] = node_id

    " Recursively add children if the node is expanded
    if is_parent && is_expanded
      let child_lines = s:render_tree(node.children, a:expanded_nodes, a:indent_level + 1, a:line_map, line)
      call extend(lines, child_lines)
    endif
  endfor
endfunction
function! s:render_tree(tree, expanded_nodes, indent_level, line_map, init_line) abort
  " Recursive function to render tree into lines
  let lines = []
  for node in a:tree
    let node_id = node.id
    let is_parent = has_key(node, 'children') && len(node.children) > 0
    let is_expanded = index(a:expanded_nodes, node_id) >= 0
    call add(lines, repeat('  ', a:indent_level) . s:print_node(node, is_parent, is_expanded))

    " Map the line number to the current node ID
    let line = len(lines) + a:init_line
    let a:line_map[line] = node_id

    " Recursively add children if the node is expanded
    if is_parent && is_expanded
      let child_lines = s:render_tree(node.children, a:expanded_nodes, a:indent_level + 1, a:line_map, line)
      call extend(lines, child_lines)
    endif
  endfor
  return lines
endfunction

function! s:print_node(node, is_parent, is_expanded)
    let prefix = a:is_parent ? (a:is_expanded ? '▾ ' : '▸ ') : '• '
    return prefix . a:node.name
endfunction

" ------------------------
" Helper Function: Find Node by ID
" ------------------------

function! s:find_node_by_id(tree, target_id) abort
  " Recursive search for the node with the given ID
  for node in a:tree
    if node.id ==# a:target_id
      " Found the node
      return node
    endif
    if has_key(node, 'children') && !empty(node.children)
      " Recursively search in the children
      let result = s:find_node_by_id(node.children, a:target_id)
      if !empty(result)
        return result
      endif
    endif
  endfor
  return {}
endfunction

" ------------------------
" Expand/Collapse Nodes
" ------------------------

function! treesitter_tree#toggle_node() abort
  " Toggle the expansion of the clicked node
  let line_nr = line('.') " Current line number
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    silent message "No node associated with the current line"
    return
  endif

  " Find the node in the tree structure by its ID
  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  " If the current node has no children, don't re-render
  if !has_key(current_node, 'children') || empty(current_node.children)
    silent message "This node has no children to expand or collapse"
    return
  endif

  if index(b:expanded_nodes, node_id) >= 0
    " If the node is expanded, collapse it
    call remove(b:expanded_nodes, index(b:expanded_nodes, node_id))
  else
    " If the node is collapsed, expand it
    call add(b:expanded_nodes, node_id)
  endif

  " Re-render the tree to reflect changes
  call s:render_tree_buffer()
endfunction

function! treesitter_tree#expand_node() abort
  " Expand the current node (zo - open fold)
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  if !has_key(current_node, 'children') || empty(current_node.children)
    return
  endif

  " Add to expanded nodes if not already expanded
  if index(b:expanded_nodes, node_id) < 0
    call add(b:expanded_nodes, node_id)
    call s:render_tree_buffer()
  endif
endfunction

function! treesitter_tree#collapse_node() abort
  " Collapse the current node (zc - close fold)
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  " Remove from expanded nodes if currently expanded
  let idx = index(b:expanded_nodes, node_id)
  if idx >= 0
    call remove(b:expanded_nodes, idx)
    call s:render_tree_buffer()
  endif
endfunction

function! treesitter_tree#expand_node_recursive() abort
  " Recursively expand current node and all children (zO)
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  if !has_key(current_node, 'children') || empty(current_node.children)
    return
  endif

  " Add current node and all its children to expanded nodes
  call add(b:expanded_nodes, node_id)
  let child_ids = s:get_all_child_ids(current_node)
  for child_id in child_ids
    if index(b:expanded_nodes, child_id) < 0
      call add(b:expanded_nodes, child_id)
    endif
  endfor

  call s:render_tree_buffer()
endfunction

function! treesitter_tree#collapse_node_recursive() abort
  " Recursively collapse current node and all children (zC)
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  " Remove current node and all its children from expanded nodes
  let idx = index(b:expanded_nodes, node_id)
  if idx >= 0
    call remove(b:expanded_nodes, idx)
  endif

  let child_ids = s:get_all_child_ids(current_node)
  for child_id in child_ids
    let idx = index(b:expanded_nodes, child_id)
    if idx >= 0
      call remove(b:expanded_nodes, idx)
    endif
  endfor

  call s:render_tree_buffer()
endfunction

" ------------------------
" Helper Function: Get All Node IDs Recursively
" ------------------------

function! s:get_all_child_ids(node) abort
  " Get all child node IDs recursively
  let ids = []
  if has_key(a:node, 'children') && !empty(a:node.children)
    for child in a:node.children
      call add(ids, child.id)
      call extend(ids, s:get_all_child_ids(child))
    endfor
  endif
  return ids
endfunction

function! s:get_all_node_ids(tree) abort
  " Get all node IDs in the tree
  let ids = []
  for node in a:tree
    call add(ids, node.id)
    call extend(ids, s:get_all_child_ids(node))
  endfor
  return ids
endfunction

" ------------------------
" Expand/Collapse Nodes
" ------------------------
function! treesitter_tree#toggle_node_recursive() abort
  " Recursively toggle current node and all children (zA)
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  if !has_key(current_node, 'children') || empty(current_node.children)
    return
  endif

  " Check if currently expanded
  if index(b:expanded_nodes, node_id) >= 0
    " Collapse recursively
    call treesitter_tree#collapse_node_recursive()
  else
    " Expand recursively
    call treesitter_tree#expand_node_recursive()
  endif
endfunction

function! treesitter_tree#expand_all() abort
  " Expand all nodes (zr - reduce folds)
  let b:expanded_nodes = s:get_all_node_ids(g:tree_struct)
  call s:render_tree_buffer()
endfunction

function! treesitter_tree#collapse_all() abort
  " Collapse all nodes (zm - fold more)
  let b:expanded_nodes = []
  call s:render_tree_buffer()
endfunction

" ------------------------
" Highlight
" ------------------------

function! treesitter_tree#highlight_node_location() abort
  " Get the current node
  let line_nr = line('.')
  let node_id = get(b:line_to_node, line_nr, -1)

  if node_id == -1
    return
  endif

  " Find the node in the tree structure by its ID
  let current_node = s:find_node_by_id(g:tree_struct, node_id)

  if empty(current_node)
    return
  endif

  " Check if node has location information
  if !has_key(current_node, 'start_point') || !has_key(current_node, 'end_point')
    return
  endif

  " Get start and end points
  let start_point = current_node.start_point
  let end_point = current_node.end_point

  if type(start_point) != type([]) || len(start_point) < 2 ||
   \ type(end_point) != type([]) || len(end_point) < 2
    echo "Invalid location data"
    return
  endif


  " Get the target buffer
  if !exists('b:source_buffer') || !bufexists(b:source_buffer)
    return
  endif

  "Store current window
  let wid = win_getid()

  " Check if source buffer is already visible in a window
  let source_win = bufwinnr(b:source_buffer)

  if source_win == -1
    " Buffer not visible, open it in a vertical split
    execute 'vsplit | buffer' b:source_buffer
  else
    " Switch to the window showing the source buffer
    execute source_win . 'wincmd w'
  endif

  " Convert tree-sitter points to Vim positions
  let start_line = start_point[0] + 1
  let start_col = start_point[1] + 1
  let end_line = end_point[0] + 1
  let end_col = end_point[1] + 1

  " Clear previous highlights
  if exists('w:node_highlight_id')
    call matchdelete(w:node_highlight_id)
  endif

  " Jump to start position and center
  call cursor(start_line, start_col)
  normal! zz

  " Highlight the range
  " For single line
  if start_line == end_line
    let w:node_highlight_id = matchaddpos('Visual', [[start_line, start_col, end_col - start_col + 1]])
  else
    " Multi-line selection - highlight each line
    let positions = []

    " First line (from start_col to end of line)
    let first_line_len = col([start_line, '$']) - start_col
    call add(positions, [start_line, start_col, first_line_len])

    " Middle lines (entire lines)
    for line in range(start_line + 1, end_line - 1)
      call add(positions, [line])
    endfor

    " Last line (from beginning to end_col)
    call add(positions, [end_line, 1, end_col])

    let w:node_highlight_id = matchaddpos('Visual', positions)
  endif

  " Set up autocmd to clear highlight when cursor moves
  augroup TreeNodeHighlight
    autocmd!
    autocmd CursorMoved,CursorMovedI <buffer> call s:clear_node_highlight()
  augroup END
  "Return to tree buffer
  call win_gotoid(wid)
endfunction

function! s:clear_node_highlight() abort
  if exists('w:node_highlight_id')
    call matchdelete(w:node_highlight_id)
    unlet w:node_highlight_id
  endif
  autocmd! TreeNodeHighlight
endfunction

" ------------------------
" Jump to node from source
" ------------------------

function! treesitter_tree#jump_to_tree_node_with_expand() abort
  let l:current_buf = bufnr('%')
  let l:current_line = line('.') - 1
  let l:current_col = col('.') - 1

  call treesitter#show_ast()
  let l:tree_bufnr = treesitter_utils#find_tree_buffer()

  " Find the node
  let l:node = s:find_node_at_position(g:tree_struct, l:current_line, l:current_col)

  if empty(l:node)
    echo "No node found at cursor position"
    return
  endif

  " Expand all parent nodes to make this node visible
  call s:expand_path_to_node(l:node.id)

  " Switch to tree buffer
  let l:tree_win = bufwinnr(l:tree_bufnr)
  if l:tree_win == -1
    execute 'vsplit | buffer' l:tree_bufnr
  else
    execute l:tree_win . 'wincmd w'
  endif

  " Re-render to show expanded nodes
  call s:render_tree_buffer()

  " Find and jump to the line
  let l:tree_line = s:find_tree_line_for_node(l:node.id)

  if l:tree_line > 0
    call cursor(l:tree_line, 1)

        " Skip indentation and indicator to position at node name
    " Find first non-whitespace, then skip the indicator (▶/▾/•)
    normal! ^
    " Move past the indicator and space
    if getline('.') =~ '^\s*[▶▾•]\s'
      call search('\S', 'c', line('.'))  " Find first non-space
      call search('\s', '', line('.'))   " Find space after indicator
      call search('\S', '', line('.'))   " Find start of node name
    endif

    normal! zz

    "echo "Jumped to: " . l:node.name
  else
    echo "Could not locate node in tree view"
  endif
endfunction

function! s:expand_path_to_node(target_id) abort
  " Find all parent nodes and expand them
  let l:path = s:find_path_to_node(g:tree_struct, a:target_id, [])

  " Get expanded nodes list from tree buffer
  let l:tree_bufnr = treesitter_utils#find_tree_buffer()
  let l:expanded = getbufvar(l:tree_bufnr, 'expanded_nodes', [])

  " Add all parents to expanded list
  for node_id in l:path
    if index(l:expanded, node_id) == -1
      call add(l:expanded, node_id)
    endif
  endfor

  " Update the tree buffer's expanded list
  call setbufvar(l:tree_bufnr, 'expanded_nodes', l:expanded)
endfunction

function! s:find_path_to_node(tree, target_id, path) abort
  " Recursively find the path (list of node IDs) to target node
  for node in a:tree
    let l:current_path = a:path + [node.id]

    if node.id == a:target_id
      return l:current_path
    endif

    if has_key(node, 'children') && !empty(node.children)
      let l:result = s:find_path_to_node(node.children, a:target_id, l:current_path)
      if !empty(l:result)
        return l:result
      endif
    endif
  endfor

  return []
endfunction

function! s:find_node_at_position(tree, line, col) abort
  " Recursively search for the deepest node containing the position
  let l:best_node = {}

  for node in a:tree
    if !has_key(node, 'start_point') || !has_key(node, 'end_point')
      continue
    endif

    let l:start_line = node.start_point[0]
    let l:start_col = node.start_point[1]
    let l:end_line = node.end_point[0]
    let l:end_col = node.end_point[1]

    " Check if cursor is within this node's range
    if (a:line > l:start_line || (a:line == l:start_line && a:col >= l:start_col))
      \ && (a:line < l:end_line || (a:line == l:end_line && a:col <= l:end_col))

      " This node contains the position
      let l:best_node = node

      " Check if any child node is more specific
      if has_key(node, 'children') && !empty(node.children)
        let l:child_node = s:find_node_at_position(node.children, a:line, a:col)
        if !empty(l:child_node)
          let l:best_node = l:child_node
        endif
      endif

      break
    endif
  endfor

  return l:best_node
endfunction

function! s:find_tree_line_for_node(node_id) abort
  " Find which line in the tree buffer shows this node
  " Uses the b:line_to_node mapping from the tree buffer
  for [line, id] in items(b:line_to_node)
    if id == a:node_id
      return str2nr(line)
    endif
  endfor
  return -1
endfunction

