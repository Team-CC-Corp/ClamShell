# [ClamShell](http://www.computercraft.info/forums2/index.php?/topic/20678-clamshell-advanced-shell-with-a-shell-language-and-bash-like-piping/)

Extended shell for ComputerCraft

## Pipelining

Pipelining allows programs to be made small and modular. Programs with their output piped won't print to the terminal. Instead, they'll print to whatever they're being piped to. If that's another program, then that program will get the first program's output from its read() calls instead of the normal keyboard input.

Let's look at two programs, ls and glep. Glep is ClamShell's equivalent to Unix's grep, which is a program that filters the lines of a file or its standard input. The major difference is that glep uses Lua patterns instead of regex. And ls of course just lists the current (or specified) directory.

```bash
ls | glep sh
```

This command will pipe ls into glep, whose argument tells it to filter out lines that don't have "sh" in them somewhere. The output of this command will be all the files in the current directory that have "sh" in their names. (Also worth noting, ClamShell reimplements ls so that it outputs in lines instead of the pretty formatting, but only when it's being piped into something else).

You can also pipe into files.

```bash
ls | glep sh > out.txt
```
you can also append to files
```bash
ls | glep sh >> out.txt
```

## Bish
ClamShell doesn't parse commands the same way as the CraftOS shell. CraftOS's shell looks for a program name followed by arguments and that's it. ClamShell uses a scripting language with some features that CraftOS's shell can't manage.

ClamShell scripts can be written inline, but you'll need semi-colons after each command if you want to do more than one. Or you can save scripts in .sh files, which ClamShell can run.
```bash
DIR = "someDir"
if test -d $DIR {
        echo "$DIR is a directory!"
}
```

Two features are demonstrated here:

 - `DIR = "someDir"`: Here we see a shell environment variable being set. Whenever $DIR is encountered, it will be replaced with the string "someDir".
 - `if test -d $DIR {`: An if statement in ClamShell runs a command and sees if it errors. If it exits cleanly, the if block executes, else it is skipped.

Files written in ClamShell's language can be run from the command line just like any other, although it is recommended that you run them under a child shell via `sh my_script.sh` since they can declare and modify environment variables.

## Additional programs

ClamShell includes several command line tools that make use of ClamShell's features.

 - `cat {files}` Cat will print the contents of one or more files. Or, if no file is passed, it will repeat the standard input.
 - `echo {arguments}` Echo will print the arguments with a space between them.
 - `glep (pattern) {files}` Glep will read from either the standard input, or a list of files, and print only the lines that match with the Lua pattern.
 - `test (-d|-e|-f) (file)` Test takes two arguments. -d, -e, and -f indicate a test for directory, existence, or file respectively. If the given file is described by the argument specified, test will exit cleanly. Else, it will error.
 - `xargs (command) {arguments}` xargs is used to take lines from the standard input and use them as arguments for a program.

## Other features
ClamShell adds a whole host of other features to the default shell:

 - History and current directory are saved between sessions
 - Scrollback on your history
 - Keyboard shortcuts:
  - <kbd>Ctrl+U</kbd> / <kbd>Ctrl+K</kbd> Clear text before/after cursor
  - <kbd>Ctrl+A</kbd> / <kbd>Ctrl+E</kbd> Jump left/right by one word
