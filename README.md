# jupynava.nvim

*jupynava.nvim* brings the power of Jupyter notebooks into the efficient and customizable environment of Neovim. This extension is designed for developers and data scientists who love working in Neovim and want to integrate Python, Jupyter notebooks, and data visualization seamlessly into their development workflow.

# Installation

For `packer.nvim`:

```lua
use { 'hermabr/jupynava.nvim', run = ':UpdateRemotePlugins' }
```

For `vim-plug`:

```vim
Plug 'hermabr/jupynava.nvim', { 'do': ':UpdateRemotePlugins' }
```

## Features (coming soon)

- *Integrated Jupyter Experience*: Utilize the built-in terminal of Neovim to run Jupyter notebooks directly within your editor.
- *Code Snippet Execution*: Send code snippets to an IPython shell effortlessly, enhancing your interactive coding experience. Inspired by packages such as [nvim-send-to-term](https://github.com/mtikekar/nvim-send-to-term).
- *Rich Visualization*: Display plots and graphics inline using the [kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/), making data analysis more interactive and visually appealing.
- *Notebook Editing*: Open, edit, and manage Jupyter notebooks as if they were Python files, providing a smooth transition between editing and executing code.

## TODO

- [x] Toggle IPython shell in terminal
- [x] Send and execute code snippets in IPython
- [ ] Open and edit Jupyter notebooks as Python files
- [ ] Support for Matplotlib visualization ([kitty](https://sw.kovidgoyal.net/kitty/graphics-protocol/))
- [ ] Manage notebook cells within Neovim
- [ ] Session management, such as starting, stopping and switching between kernels
- [ ] Support for other languages, such as Julia, R, etc.
- [ ] Support running cells in the background with outputs similar to Jupter notebooks or VSCode Jupyter extension, and not in a seperate terminal
