# Pattern: Terminal keyboard shortcuts (huge speed win)

These work in bash/zsh out of the box (the "readline" library).

## Editing the current line

```text
Ctrl+A        move the cursor to the START of the line
Ctrl+E        move the cursor to the END of the line
Ctrl+U        delete everything BEFORE the cursor
Ctrl+K        delete everything AFTER the cursor
Ctrl+W        delete the WORD before the cursor
Ctrl+Y        paste back what you just deleted with Ctrl+U/K/W
Ctrl+L        clear the screen (same as "clear", keeps your typed command)
Alt+B         move back one word        Alt+F  move forward one word
Ctrl+T        swap the two characters around the cursor (fix typos fast)
Ctrl+_        undo
```

## Running and controlling commands

```text
Tab           auto-complete a name      Tab Tab   show all possible completions
Enter         run the command
Ctrl+C        CANCEL/kill the running command (the "get me out" key)
Ctrl+Z        SUSPEND it (resume with bg or fg)
Ctrl+D        end of input — exits the shell, or saves in "cat >"
Ctrl+S        freeze output             Ctrl+Q  unfreeze it (if the terminal seems stuck, press this)
Alt+.         insert the LAST ARGUMENT of the previous command (extremely useful)
Ctrl+R        search your command history backwards
Ctrl+G        cancel the Ctrl+R search
Up / Down     walk through previous commands
```

## The three to learn first

```bash
Ctrl+R                                # never retype a long command again
Ctrl+C                                # always stop a runaway command
Alt+.                                 # reuse the previous path: mkdir a/b/c → cd Alt+.
```

## Terminal window (not shell) shortcuts

```text
Ctrl+Shift+T   new tab        Ctrl+Shift+C / V   copy / paste in the terminal
Ctrl+Shift++   zoom in        mouse wheel        scroll back
```

## Practice

Type a long command, then use Ctrl+A, Ctrl+E, Ctrl+W and Alt+. to edit it without the arrow keys.
