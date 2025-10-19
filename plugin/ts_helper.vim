" plugin/ts_helper.vim - Vimscript frontend for the Python tree-sitter helper (synchronous)
" Folding algorithm updated to produce minimal fold levels using nesting (stack) logic.
" Per-language default fold node types removed. Use g:ts_helper_fold_node_types to configure.
" Place this file and ts_helper.py in the same plugin directory.
" Optional globals:
"   let g:ts_helper_py = '/full/path/to/ts_helper.py'
"   let g:ts_helper_filetype_map = {'py': 'python', 'js': 'javascript'}
"   let g:ts_helper_auto_folds = 1
"   let g:ts_helper_fold_node_types = {}

if exists('g:loaded_ts_helper_plugin')
  finish
endif
let g:loaded_ts_helper_plugin = 1

" helper detection: default to helper file next to this script
let s:script_dir = expand('<sfile>:p:h')
if exists('g:ts_helper_py') && !empty(g:ts_helper_py)
  let s:helper_py = g:ts_helper_py
else
  let s:helper_py = s:script_dir . '/ts_helper.py'
endif

" default filetype -> tree-sitter language map; override with g:ts_helper_filetype_map
let s:default_map = {
      \ 'py': 'python',
      \ 'python': 'python',
      \ 'js': 'javascript',
      \ 'javascript': 'javascript',
      \ 'c': 'c',
      \ 'cpp': 'cpp',
      \ 'c++': 'cpp',
      \ 'java': 'java',
      \ 'rs': 'rust',
      \ 'rust': 'rust',
      \ 'go': 'go',
      \ 'yaml': 'yaml',
      \ 'yml': 'yaml',
      \ }

function! s:ft_to_lang() abort
  if exists('g:ts_helper_filetype_map')
    let m = g:ts_helper_filetype_map
  else
    let m = s:default_map
  endif
  let ft = &filetype
  if has_key(m, ft)
    return m[ft]
  endif
  if ft =~# '\.'
    let base = split(ft, '\.')[0]
    if has_key(m, base)
      return m[base]
    endif
  endif
  return ''
endfunction

" Helper: build command list (list form) and string form for systemlist fallback
function! s:build_cmd_list(lang, cmdname, args_string) abort
  let parts = ['python3', s:helper_py, '--lang', a:lang, a:cmdname]
  if a:args_string !=# ''
    let args = split(a:args_string)
    call extend(parts, args)
  endif
  return parts
endfunction

function! s:build_cmd_str(lang, cmdname, args_string) abort
  let parts = s:build_cmd_list(a:lang, a:cmdname, a:args_string)
  " Quote helper path and python3 for safety
  let quoted = map(parts, 'shellescape(v:val)')
  return join(quoted, ' ')
endfunction

" Synchronous helper caller using systemlist().
" Returns decoded JSON (Vim dict/list) or empty {} / [] on error.
function! s:call_helper_sync(cmdname, lang, args_string, input_text) abort
  if !executable('python3')
    echom 'ts_helper: python3 not found in PATH'
    return {}
  endif
  if empty(a:lang)
    echom 'ts_helper: language not provided'
    return {}
  endif

  let cmd_str = s:build_cmd_str(a:lang, a:cmdname, a:args_string)
  try
    let json_lines = systemlist(cmd_str, a:input_text)
  catch
    echom 'ts_helper: error running helper'
    return {}
  endtry

  if v:shell_error != 0
    " print stderr/combined output to messages to help debugging
    let msg = join(json_lines, "\n")
    if msg ==# ''
      let msg = 'ts_helper: helper exited with non-zero status'
    endif
    echohl ErrorMsg
    echom msg
    echohl None
    return {}
  endif

  let json_text = join(json_lines, "\n")
  if empty(json_text)
    " helper returned nothing (empty result)
    return {}
  endif
  try
    let data = json_decode(json_text)
  catch
    echohl ErrorMsg
    echom 'ts_helper: failed to parse JSON from helper'
    echohl None
    return {}
  endtry
  return data
endfunction

" build input text from current buffer
function! s:buf_text() abort
  return join(getbufline('%', 1, '$'), "\n")
endfunction

" ------------------------
" AST display & selection (synchronous)
" ------------------------

function! s:show_ast() abort
  let lang = s:ft_to_lang()
  if empty(lang)
    echo 'ts_helper: unknown language for filetype ' . &filetype
    return
  endif

  let data = s:call_helper_sync('ast', lang, '', s:buf_text())
  if empty(data)
    echo 'ts_helper: empty AST or helper error'
    return
  endif

  function! s:render_node(node, indent) abort
    if type(a:node) == type({})
      let sp = get(a:node, 'start_point', [0,0])
      let ep = get(a:node, 'end_point', [0,0])
      let t = printf('%s%s [%d:%d - %d:%d] %s',
            \ repeat('  ', a:indent),
            \ get(a:node, 'type', '<unknown>'),
            \ sp[0] + 1,
            \ sp[1],
            \ ep[0] + 1,
            \ ep[1],
            \ get(a:node, 'text', ''))
      let lines = [t]
      if has_key(a:node, 'children')
        for child in a:node.children
          let lines += s:render_node(child, a:indent + 1)
        endfor
      endif
      return lines
    endif
    return []
  endfunction

  let lines = s:render_node(data, 0)
  if empty(lines)
    echo 'ts_helper: empty AST'
    return
  endif
  vnew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  call setline(1, lines)
  setlocal nomodifiable
  file [ts-helper] AST
endfunction

function! s:select_node() abort
  let lang = s:ft_to_lang()
  if empty(lang)
    echo 'ts_helper: unknown language for filetype ' . &filetype
    return
  endif
  let cursor = getpos('.')
  let row = cursor[1] - 1
  let col = cursor[2] - 1
  let data = s:call_helper_sync('node_at', lang, printf('%d %d', row, col), s:buf_text())
  if empty(data)
    echo 'ts_helper: no node at cursor or helper error'
    return
  endif
  if !has_key(data, 'start_point') || !has_key(data, 'end_point')
    echo 'ts_helper: node missing range'
    return
  endif
  let srow = data.start_point[0]
  let scol = data.start_point[1]
  let erow = data.end_point[0]
  let ecol = data.end_point[1]
  call setpos('.', [0, srow + 1, scol + 1, 0])
  execute "normal! v"
  call setpos('.', [0, erow + 1, ecol + 1, 0])
endfunction

function! Remove_prefixes(value)
  return substitute(a:value, '^(<|>)', '', '')
endfunction

function! s:build_fold_data() abort
  let lang = s:ft_to_lang()
  if empty(lang)
    return
  endif

  let data = s:call_helper_sync('folds', lang, '', s:buf_text())
  if empty(data)
    call s:disable_folds()
    return
  endif

  " Reset temporary map
  let s:fold_levels = {}
  let nodes = []

  " Determine last line in buffer (used to detect nodes that end at EOF)
  let max_lnum = line('$')

  " Collect only relevant nodes and compute simple numeric start/end
  for node in data
    if !has_key(node, 'type') || empty(node.type) || !has_key(node, 'start_point') || !has_key(node, 'end_point')
      continue
    endif

    " Ignore nodes that start at (0,0) and end at end-of-file (prevents whole-buffer wrapper nodes)
    let sp_row = node.start_point[0]
    let sp_col = node.start_point[1]
    let ep_row = node.end_point[0]
    if sp_row == 0 && sp_col == 0 && ep_row ==# (max_lnum - 1)
      continue
    endif

    " Special-case: for YAML ignore wrapper node types 'stream' and 'document'
    if lang ==# 'yaml'
      if node.type !=# 'block_mapping_pair' && node.type !=# 'block_sequence_item'
        continue
      endif
    endif

    " Only nodes that span multiple lines are foldable
    let sp = node.start_point[0]
    let ep = node.end_point[0]
    if ep <= sp
      continue
    endif

    " append a simplified node record
    call add(nodes, {'type': node.type, 's': sp, 'e': ep})
  endfor

  if empty(nodes)
    call s:disable_folds()
    return
  endif

  " sort nodes by start line then by end (smaller end first)
  call sort(nodes, {a,b -> a.s == b.s ? a.e - b.e : a.s - b.s})

  " Use a stack to compute nesting depth: only count nodes that are strictly nested.
  let stack = []

  for n in nodes
    " Pop stack until current node is nested inside top of stack
    while !empty(stack)
      let top = stack[-1]
      " if n is nested inside top (start >= top.s and end <= top.e) -> nested
      if n.s >= top.s && n.e <= top.e
        break
      endif
      " otherwise pop top (we've left that ancestor)
      call remove(stack, -1)
    endwhile

    " Depth is stack size + 1 (top-level nodes have depth 1)
    let depth = len(stack) + 1

    " Record fold level for lines inside the node (start+1 .. end inclusive)
    let sline = n.s + 1
    let eline = n.e + 1
    if sline < 1
      let sline = 1
    endif
    if eline > max_lnum
      let eline = max_lnum
    endif

    for l in range(sline, eline)
      let key = string(l)
      let cur = get(s:fold_levels, key, 0)
      " assign the maximum depth seen for that line (nested deeper wins)
      if depth > cur
        let prefix = ''
        if l == sline
          let prefix = '>'
        endif
        if l == eline
          let prefix = '<'
        endif
        let s:fold_levels[key] = prefix . depth
      endif
    endfor

    " push current node onto stack as potential ancestor for following nodes
    call add(stack, n)
  endfor

  let values = uniq(sort(values(map(copy(s:fold_levels), 'Remove_prefixes(v:val)')), 'n'))

  for key in keys(s:fold_levels)
    let level = s:fold_levels[key]
    let contains_init_fold = stridx(level, '>') == 0 
    let contains_end_fold = stridx(level, '<') == 0 
    if contains_init_fold || contains_end_fold
      let level = Remove_prefixes(level)
    endif
    let prefix = ''
    if contains_init_fold
      let prefix = '>'
    endif
    if contains_end_fold
      let prefix = '<'
    endif
    let s:fold_levels[key] = prefix . (index(values, level) + 1)   
  endfor

  " Save to buffer-local map for foldexpr to consult
  let b:ts_helper_fold_levels = copy(s:fold_levels)
  " enable folding using our expression
  setlocal foldmethod=expr
  setlocal foldexpr=TsHelperFoldExpr(v:lnum)
  setlocal foldenable
endfunction

function! s:disable_folds() abort
  if exists('b:ts_helper_fold_levels')
    unlet b:ts_helper_fold_levels
  endif
  setlocal foldmethod=manual
  setlocal foldexpr=
endfunction

function! TsHelperFoldExpr(lnum) abort
  if exists('b:ts_helper_fold_levels')
    return get(b:ts_helper_fold_levels, string(a:lnum), 0)
  endif
  return 0
endfunction

" Commands for folds
command! TSHBuildFolds call s:build_fold_data()
command! TSHEnableFolds call s:build_fold_data()
command! TSHDisableFolds call s:disable_folds()

" ------------------------
" Symbol navigation (synchronous)
" ------------------------

function! s:goto_symbol(next) abort
  let lang = s:ft_to_lang()
  if empty(lang)
    echo 'ts_helper: unknown language for filetype ' . &filetype
    return
  endif

  let data = s:call_helper_sync('symbols', lang, '', s:buf_text())
  if type(data) != type([]) || empty(data)
    echo 'ts_helper: no symbols found'
    return
  endif
  let cursor = getpos('.')
  let crow = cursor[1] - 1
  let ccol = cursor[2] - 1
  let idx = -1
  for i in range(len(data))
    let item = data[i]
    if has_key(item, 'start_point')
      let sr = item.start_point[0]
      let sc = item.start_point[1]
      if sr > crow || (sr == crow && sc > ccol)
        let idx = i
        break
      endif
    endif
  endfor
  if a:next
    if idx == -1
      let idx = 0
    endif
  else
    if idx == -1
      let idx = len(data) - 1
    else
      let idx = max([0, idx - 1])
    endif
  endif
  if idx < 0 || idx >= len(data)
    echo 'ts_helper: no symbol to jump to'
    return
  endif
  let dest = data[idx]
  if has_key(dest, 'start_point')
    call setpos('.', [0, dest.start_point[0] + 1, dest.start_point[1] + 1, 0])
    normal! zt
  endif
endfunction

" Commands for AST/selection/navigation
command! TSHShowAST call s:show_ast()
command! TSHSelectNode call s:select_node()
command! TSHNextSym call s:goto_symbol(1)
command! TSHPrevSym call s:goto_symbol(0)

"" default keymaps (optional)
"if !exists('g:ts_helper_keymaps') || g:ts_helper_keymaps
"  nnoremap <silent> <leader>ta :TSHShowAST<CR>
"  nnoremap <silent> <leader>ts :TSHSelectNode<CR>
"  nnoremap <silent> <leader>tn :TSHNextSym<CR>
"  nnoremap <silent> <leader>tp :TSHPrevSym<CR>
"endif

" Auto-build folds on read if enabled
if !exists('g:ts_helper_auto_folds')
  let g:ts_helper_auto_folds = 1
endif

if g:ts_helper_auto_folds
  augroup ts_helper_folds
    autocmd!
    autocmd BufReadPost,BufNewFile * if empty(&filetype) | else | call s:maybe_build_folds() | endif
  augroup END
endif

function! s:maybe_build_folds() abort
  " avoid running on the helper script buffer itself
  if expand('%:p') =~# 'ts_helper.py$'
    return
  endif
  let lang = s:ft_to_lang()
  if empty(lang)
    return
  endif
  call s:build_fold_data()
endfunction
