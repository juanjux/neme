### Future home of the Neme text editor

![idiotez](https://i.imgflip.com/1le4it.jpg)

I've just started to work on this so there isn't really nothing usable 
(but hey, I've a nice [gap buffer
implementation](https://github.com/juanjux/neme/blob/master/src/backend/d/gapbuffer.d) 
in D!).

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

For the moment I'm just toying around with different languages (currently D) 
and my short term plan is to implement a library with several text manipulation
data structures (line list, gap buffer, a bastard son of both, etc) and another library on top of them
implementing text-manipulation primitives.
