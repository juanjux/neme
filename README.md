### Future home of the Neme text editor

![idiotez](https://i.imgflip.com/1le4it.jpg)

There isn't really nothing usable as a text editor yet here
(but I've a nice [gap buffer implementation](https://github.com/juanjux/neme/blob/master/src/core/gapbuffer.d) 
in D).

The World Domination Plan for this repo is to contain the Neme text editor 
(Neme = NEw Modal Editor). As the name implies, I'm going to explore 
new ways to do modal editing. When one says "modal editor" Vi/Vim 
automatically comes to mind because there isn't really much beyond it, 
unlike what happened with Emacs-style text editing that gave birth to
most of what non modal editors use today.

Vim is awesome (I've been using it for 21 years) but I think it can be fun
to reinvent this wheel and see what can come out of it. After all, Vim 
was designed for [another keyboard](https://en.wikipedia.org/wiki/Vi#/media/File:KB_Terminal_ADM3A.svg)
and requirements and environments that are pretty different from what we 
use today.

Current status:

- Stable and very performant and feature complete [gapbuffer](https://en.wikipedia.org/wiki/Gap_buffer)
implementation.

- Simple "ed-like" line text editor used for integration and performance testing.

- ncurses TUI that currently can be used to read files like the less or more
commands.

Roadmap:

- Develop the TUI into a full featured ncurses text editor with configurable
keyboard control "personalities" so you could use it like Vim or Emacs just
changing a config setting.

- Implement a plugin system. Plugins will be implemented in D so no shitty 
scripting language will cause slowdowns like happens with other editors.

- Provide a graphical interface using Gtkd.

### Building

Default build will create a `neme` binary that will run some benchmarks using
low level methods over the GapBuffer and high level operations using text
objects. If you want to build:

```sh
dub build
```

For the best performance use instead:

```
dub build --compiler=ldc2 --build=release --config=optimized
```
