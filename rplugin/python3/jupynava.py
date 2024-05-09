import neovim
import nbformat
from pathlib import Path
from nbformat.v4 import new_notebook, new_code_cell, new_markdown_cell
import re

@neovim.plugin
class Jupynava(object):
    def __init__(self, nvim):
        self.nvim = nvim

    @neovim.autocmd('BufRead', pattern='*.ipynb', sync=True)
    def on_open(self):
        buffer_content = "\n".join(self.nvim.current.buffer[:])
        if buffer_content.strip():
            from io import StringIO
            f = StringIO(buffer_content)
            try:
                nb = nbformat.read(f, as_version=4)
                script_content = self.create_script_from_notebook(nb)
                self.nvim.current.buffer[:] = script_content.splitlines()
            except Exception as e:
                self.nvim.err_write(f"Error parsing notebook: {str(e)}\n")

    @neovim.autocmd('BufWritePre', pattern='*.ipynb', sync=True)
    def on_save_pre(self):
        self.nvim.command('setlocal nomodifiable')
        try:
            script_content = "\n".join(self.nvim.current.buffer[:])
            script_path = Path(self.nvim.current.buffer.name).with_suffix('.py')
            nb = self.create_notebook_from_script(script_content)
            nbformat.write(nb, str(script_path.with_suffix('.ipynb')))
            self.nvim.command('edit!')
            self.nvim.command('set nomodified')
        finally:
            self.nvim.command('setlocal modifiable')

    @neovim.autocmd('BufWritePost', pattern='*.ipynb', sync=True)
    def on_save_post(self):
        buffer_content = "\n".join(self.nvim.current.buffer[:])
        if buffer_content.strip():
            from io import StringIO
            f = StringIO(buffer_content)
            try:
                nb = nbformat.read(f, as_version=4)
                script_content = self.create_script_from_notebook(nb)
                self.nvim.current.buffer[:] = script_content.splitlines()
            except Exception as e:
                self.nvim.err_write(f"Error parsing notebook: {str(e)}\n")

    def create_script_from_notebook(self, nb):
        lines = []
        previous_cell_markdown = False
        for cell in nb.cells:
            if cell.cell_type == 'code':
                if lines and lines[-1] != "# +":
                    if not previous_cell_markdown:
                        lines.append('\n')
                    lines.append('# +\n')
                    lines.append('\n')
                lines.append(cell.source + '\n')
                previous_cell_markdown = False
            elif cell.cell_type == 'markdown':
                if lines:
                    lines.append('\n')
                lines.append('# -\n')
                markdown_lines = cell.source.split('\n')
                for md_line in markdown_lines:
                    lines.append('# ' + md_line + '\n')
                previous_cell_markdown = True
        return ''.join(lines)

    def create_notebook_from_script(self, script_content):
        parts_with_delimiters = re.split(r'(^# [\+\-]$)', script_content, flags=re.MULTILINE)
        notebook = new_notebook()
        current_delimiter = None
        for part in parts_with_delimiters:
            if part.strip() in ['# +', '# -']:
                current_delimiter = part.strip()
            else:
                if current_delimiter == '# -':
                    stripped_part = '\n'.join(line[2:].rstrip() if line.startswith('# ') else line.rstrip() for line in part[1:-1].split('\n'))
                    notebook.cells.append(new_markdown_cell(stripped_part))
                else:
                    stripped_part = part.strip('\n')
                    if stripped_part:
                        notebook.cells.append(new_code_cell(stripped_part))
                current_delimiter = None
        return notebook
