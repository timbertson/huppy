# huppy

<img src="http://gfxmonk.net/dist/status/project/huppy.png">

Some servers and long-running processes restart themselves cleanly when they receive the `HUP` signal. But many don't. If yours doesn't, and you want a development-friendly way to restart your server, you should use `huppy`. It'll run your server (or other long-running process), and when you send it the `HUP` signal it'll kill and restart your process for you.

Your process should terminate gracefully when it receives `SIGINT` (i.e `ctrl-c`). In particular, make sure you clean up any child processes, as huppy won't kill those.

# Usage:

	$ huppy python -m SimpleHTTPServer
	[ huppy ] Running python (pid 3641)
	Serving HTTP on 0.0.0.0 port 8000 ...
	
	# in another terminal, run:
	$ killall -HUP huppy
	
	Traceback (most recent call last):
	  [ ... ]
	KeyboardInterrupt
	[ huppy ] Restarted python (pid 3667)
	Serving HTTP on 0.0.0.0 port 8000 ...

# Building & Installing

Get the dependencies ([gup](https://github.com/gfxmonk/gup/) and ocaml), and then:

	$ # compile into bin/huppy
	$ gup
	
	$ # install (optional)
	$ gup install # (installs into $DESTDIR/bin)
