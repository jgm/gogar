# GOGAR

GOGAR ("the game of giving and asking for reasons") is a simplified
model of the discursive scorekeeping practice described in Robert
Brandom's book *Making It Explicit* (Cambridge: Harvard University
Press, 1994). It is designed to help illustrate the way agents'
attributions of commitments and entitlements to each other is
affected by the speech acts of making, disavowing, and challenging
assertions.

GOGAR currently models only a part of the practice described in
Chapter 3 of *Making It Explicit*, and it makes many simplifying
assumptions. For example, it assumes that all the agents are in
earshot of each other, so that testimonial inheritance of
entitlements is universal.

[Try GOGAR on the web!](http://johnmacfarlane.net:9094/)

The current version of GOGAR is a single Ruby script,
[gogar.rb](gogar.rb). After downloading it, you can run it with the
following command:

    ruby gogar.rb

You may need to install [Ruby](http://www.ruby-lang.org) first.
There's an installer for Windows
[here](http://rubyforge.org/frs/?group_id=167). Mac OSX comes
with a version of ruby.

You can also run GOGAR as a web application, as follows:

    ruby gogar.rb -w

By default, GOGAR will run on port 9094, so point your browser to
<http://localhost:9094/> and you should see it.  An alternative port
can be specified as follows:

    ruby gogar.rb -w 7000

GOGAR carries no warranties of any kind.

