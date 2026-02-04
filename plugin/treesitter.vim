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

" Define the tree structure
let g:tree_struct = []

" helper detection: default to helper file next to this script
let s:plugin_root = expand('<sfile>:p:h:h')
if !exists('g:ts_helper_py') || empty(g:ts_helper_py)
  let g:ts_helper_py = s:plugin_root . '/python/ts_helper.py'
endif

" Commands for AST/selection/navigation
command! TSHShowAST call treesitter#show_ast()
command! TSHSelectNode call treesitter#select_node()
command! TSHNextSym call treesitter#goto_symbol(1)
command! TSHPrevSym call treesitter#goto_symbol(0)
command! TSHShowLevels call treesitter#show_fold_level()

" default keymaps (optional)
if !exists('g:ts_helper_keymaps') || g:ts_helper_keymaps
  nnoremap <silent> <leader>tta :TSHShowAST<CR>
  nnoremap <silent> <leader>ttl :TSHShowLevels<CR>
  "nnoremap <silent> <leader>ts :TSHSelectNode<CR>
  "nnoremap <silent> <leader>tn :TSHNextSym<CR>
  "nnoremap <silent> <leader>tp :TSHPrevSym<CR>
endif

" Auto-build folds on read if enabled
if !exists('g:ts_helper_auto_folds')
  let g:ts_helper_auto_folds = 1
endif

if g:ts_helper_auto_folds
  augroup ts_helper_folds
    autocmd!
    autocmd BufReadPost,BufNewFile * if empty(&filetype) | else | call treesitter#maybe_build_folds() | endif
  augroup END
endif

" ------------------------
" Key Mappings
" ------------------------

command! JumpToASTNode call treesitter_tree#jump_to_tree_node_with_expand()

" Map "Enter" key to toggle expand/collapse behavior
autocmd FileType tree nnoremap <buffer> <CR> :call treesitter_tree#toggle_node()<CR>

" Fold-like mappings
autocmd FileType tree nnoremap <buffer> za :call treesitter_tree#toggle_node()<CR>
autocmd FileType tree nnoremap <buffer> zo :call treesitter_tree#expand_node()<CR>
autocmd FileType tree nnoremap <buffer> zc :call treesitter_tree#collapse_node()<CR>
autocmd FileType tree nnoremap <buffer> zO :call treesitter_tree#expand_node_recursive()<CR>
autocmd FileType tree nnoremap <buffer> zC :call treesitter_tree#collapse_node_recursive()<CR>
autocmd FileType tree nnoremap <buffer> zA :call treesitter_tree#toggle_node_recursive()<CR>
autocmd FileType tree nnoremap <buffer> zr :call treesitter_tree#expand_all()<CR>
autocmd FileType tree nnoremap <buffer> zm :call treesitter_tree#collapse_all()<CR>
autocmd FileType tree autocmd CursorMoved <buffer> call treesitter_tree#highlight_node_location()
