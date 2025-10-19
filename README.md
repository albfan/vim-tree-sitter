# vim-tree-sitter

Vim plugin relying on tree-sitter for advanced source code features.

## Disclaimer

This plugin is experimental, is encouraged to use neovim tree-sitter plugin implementation

## Features
- code folding
- :TSHShowAST — open a scratch vertical split showing the AST for the current buffer
- :TSHSelectNode — visually select the smallest named tree-sitter node under the cursor
- :TSHNextSym / :TSHPrevSym — jump to the next / previous function/class-like symbol


## Requirements (simple)
- Vim 8.x
- Python 3
- Python packages:
  - pip install tree-sitter
  - and for each language either install the language package:
    - pip install tree-sitter-python
    - pip install tree-sitter-yaml
    - pip install tree-sitter-javascript
    - ... (module names follow tree_sitter_<language>)

## Credits:

- [tree-sitter](https://github.com/tree-sitter/tree-sitter)
- [tree-sitter python bindings](https://github.com/tree-sitter/py-tree-sitter)
- [nvim tree-sitter](https://github.com/nvim-treesitter/nvim-treesitter)
