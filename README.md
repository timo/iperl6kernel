iperl6kernel
============

This is the attempt to expose an "ipython kernel" interface for a rakudo process.

ipython kernels communicate with one or more frontends (terminals) using ZeroMQ sockets.

Roadmap
-------

The first two steps are

 - Create a simple shim that connects rakudo with "ipython console"
 - Create an alternative rakudo REPL that talks to the shim via a simple protocol over stdin/stdout

After that, there's a bit of work to be done, that can be worked on in any order:

 - Bring Net::ZeroMQ forwards enough, so that the shim can be re-written in perl6.
 - Port over STDs "is this statement finished?" detection to HLL::Grammar and then to Rakudo


Links and stuff
---------------

IPython ZeroMQ Protocol: http://ipython.org/ipython-doc/rel-0.13.1/development/messaging.html
