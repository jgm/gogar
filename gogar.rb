#!/usr/bin/env ruby
# Gogar.rb - gogar in ruby
# 
#   GOGAR - the game of giving and asking for reasons.
#   A partial simulation of the scorekeeping dynamics from Chapter 3 
#   of Robert Brandom's book Making It Explicit (Harvard, 1994).
#   (c) 2006 John MacFarlane.  This software carries no warranties
#   of any kind. 

require 'set'
require 'webrick'
require 'cgi'
include WEBrick

class Set
  def to_s
    "{" + self.to_a.join(", ") + "}"
  end
end

class EqSet < Set
  def add item 
    if not any? {|x| x == item}
      super.add item 
    end
  end

  def delete item 
    super.delete_if {|x| x == item}
  end
end

class Inference
  def initialize(premises, conclusion)  # premises a list
    @premises = EqSet.new premises
    @conclusion = conclusion
  end
  attr_reader :premises, :conclusion
  
  def == inf
    (@premises == inf.premises) && (@conclusion == inf.conclusion)
  end
  
  def to_s 
    @premises.to_s + " |- " + @conclusion.to_s
  end
end

class InferenceSet < EqSet
  def to_s
    self.to_a.join("; ")
  end
end

class IncompatibilitySet < EqSet
  def to_s
    self.to_a.join("; ")
  end
end

class Challenge
  def initialize(target, sentence)
    @target = target
    @sentence = sentence
  end
  
  attr_reader :target, :sentence

  def == chal
    @target == chal.target && @sentence == chal.sentence
  end
  
  def to_s 
    "challenged #{target.name}'s entitlement to \"#{sentence}\""
  end
end

class ChallengeSet < EqSet
  def to_s
    self.to_a.join("; ")
  end
end

def wrap(str, indent="  ")
  indent = "  "
  endline = "\n"
  width = 78
  pos = 0
  outstring = ""
  sep = ", " 
  str.split(/; |, /).each do |s|
    if pos != 0 and (pos + s.length + sep.length) > width
      outstring += endline
      outstring += indent
      pos = indent.length
    end
    outstring += s
    outstring += sep
    pos += (s.length + sep.length)
  end
  sep_pos = -1 * sep.length
  if outstring.length >= sep.length  # strip off trailing sep if there is one
    outstring[0..(sep_pos-1)]
  else
    outstring
  end
end

class Agent
  def initialize(name, 
                 committive = [[["A is red"],"A is colored"],
                                [["A is blue"],"A is colored"],
                                [["A is green"],"A is colored"]],
                 permissive = [[["A is red", "A is fragrant"], "A is edible"],
                               [["A is blue", "A is small"], "A is poisonous"]],
                 incompatibles = [["A is red", "A is blue"],
                               ["A is red", "A is green"],
                               ["A is blue", "A is green"],
                               ["A is edible", "A is poisonous"]])
    @name = name
    @intelligence = 100
    @commitments_avowed = EqSet.new []
    @incompatibilities = IncompatibilitySet.new(incompatibles.map {|i| EqSet.new i})
    @committive_inferences = InferenceSet.new(committive.map {|p,c| Inference.new p, c})
    @permissive_inferences = InferenceSet.new(permissive.map {|p,c| Inference.new p, c})
    @challenges_issued = ChallengeSet.new []
  end

  attr_accessor :name, :intelligence, :commitments_avowed, 
  :incompatibilities, :committive_inferences, :permissive_inferences, 
  :challenges_issued

  def asserts str
    @commitments_avowed.add str
  end

  def disavows str
    @commitments_avowed.delete str
  end

  def challenges(agent, str)
    if agent.commitments_avowed.member? str
      @challenges_issued.add Challenge.new(agent, str)
    else
      # wasn't asserted
    end
  end
  
  def withdraws_challenge(agent, str)
    @challenges_issued.delete Challenge.new(agent,str)
  end
  
  def to_s
    name +
      "\nIntelligence = #{intelligence}" +
      wrap("\nCommitments avowed: #{commitments_avowed.to_s}") +
      wrap("\nSets taken to be incompatible: #{incompatibilities.to_s}") +
      wrap("\nCommittive inferences accepted: #{committive_inferences.to_s}") +
      wrap("\nPermissive inferences accepted: #{permissive_inferences.to_s}") +
      wrap("\nChallenges issued: #{challenges_issued.to_s}") +
      "\n"
  end
end

class Game
  def initialize
    @agents = EqSet.new []
    @transcript = []
  end

  attr_accessor :agents, :transcript

  def reset
    agents.each { |ag| agents.delete ag }
    @transcript = []
  end

  def agent_named(name)
    agents.select { |ag| ag.name.downcase == name.downcase }[0]
  end

  def assertions_challenged(agent)
    challenged_sentences = EqSet.new []
    agents.each { |a| challenged_sentences.merge a.challenges_issued.select {|c| c.target == agent}.map { |c| c.sentence }}
    challenged_sentences
  end    
  
  def assertions_unchallenged(agent)
    agent.commitments_avowed - assertions_challenged(agent)
  end

  def all_unchallenged_assertions
    all = EqSet.new []
    self.agents.each{|a| all = all | assertions_unchallenged(a)}
    all
  end

  def consequences_once(infs, basis) 
    # returns set of consequences of applying inference to sentences in basis
    conclusions = EqSet.new
    infs.each do |inf|
      if inf.premises.subset? basis 
        conclusions.add inf.conclusion
      end
    end
    basis | conclusions
  end
  
  def compatible_with?(incompatibilities, commitments, sentence)
    # returns true iff sentence is compatible with commitments according to incompatibilities 
    all = commitments | EqSet.new([sentence])
    not incompatibilities.any? {|inc| inc.subset?(all) && (not inc.subset?(all - sentence))  }  # sentence is ruled out only if it MAKES incompatibility where there wasn't any before
  end  
  
  def remove_incompatibles(set, commitments, incompatibilities)
    # returns result of removing sentences from set that are incompatible
    # with sentences in commitments
    set.find_all {|s| compatible_with?(incompatibilities, commitments, s) }.to_set
  end
    
  def consequences_once_and_prune(infs, base, coms, incs)
    remove_incompatibles(consequences_once(infs, base), coms, incs)
  end
  
  def fixed_point(set, times, &block)
    if times == 0 
      set
    else
      nxt = block.call set
      if set == nxt
        set
      else
        fixed_point(nxt, (times - 1), &block)
      end
    end
  end
  
  def commitments(scorekeeper, other)
    # returns set of commitments scorekeeper attributes to other
    fixed_point(other.commitments_avowed, scorekeeper.intelligence) {|set| consequences_once(scorekeeper.committive_inferences, set)}
  end
  
  def incompatibles(scorekeeper, other)
    # returns set of sets of incompatible sentences that other is committed to,
    # according to scorekeeper
    IncompatibilitySet.new scorekeeper.incompatibilities.select {|inc| inc.subset? commitments(scorekeeper,other)}
  end

  def entitlements(scorekeeper, other)
    # returns the entitlements scorekeeper attributes to other
    coms = commitments(scorekeeper, other)
    incs = scorekeeper.incompatibilities
    times = other.intelligence
    # start with default entitlement to anything anyone has asserted, unless
    # it has been challenged or is incompatible with other's commitments
    base = remove_incompatibles(self.all_unchallenged_assertions, coms, incs)
    fixed_point(base, times) {|s| expand_entitlements(coms, s, incs, scorekeeper.committive_inferences, scorekeeper.permissive_inferences, times)}
  end

  def expand_entitlements(coms, ents, incs, cominfs, perminfs, times)
    # apply committive inferences, which are all permissive too,
    # removing incompatibles afterward
    ents2 = consequences_once_and_prune(cominfs, ents, coms, incs)
    # close under permissive inferences from entitled commitments only
    ents3 = consequences_once_and_prune(perminfs, (ents & coms), coms, incs)
    ents2 | ents3
  end

  def score(scorekeeper, other)
    # returns string with score of scorekeeper on other in game
    coms = commitments(scorekeeper, other)
    ents = self.entitlements(scorekeeper, other)
    incs = incompatibles(scorekeeper, other)
    wrap("\nCommitments:  #{coms.to_s}") +
      wrap("\nEntitlements: #{ents.to_s}") +
      wrap("\nIncompatibles: #{incs.to_s}") +
      "\n\n"
  end

  def score_all
    # returns score of all on all
    agents = self.agents.to_a.sort_by {|a| a.name}
    agents.map {|sk| agents.map {|ot| "#{sk.name}'s score on #{ot.name}" + self.score(sk, ot)}}.join("")
  end

  def self.startup
    "
Welcome to the game of giving and asking for reasons,
a simulation of the linguistic scorekeeping dynamics 
described in chapter 3 of Robert Brandom's book      
Making It Explicit (Harvard University Press, 1994). 

(c) 2006 John MacFarlane                              

For a list of sample commands, type help              

"
  end

  def command(inp) 
    # returns string result of processing inp in game
    result = case   
    when inp =~ /^\s*(quit|exit)\s*$/
      "Goodbye.\n"
    when inp =~ /^\s*help\s*$/
      help_message
    when inp =~ /^\s*(list)?\s*agents\s*$/
      self.agents.map {|ag| ag.to_s}.join("\n")
    when inp =~ /^\s*add\s*agent\s+(\w+)\s*$/
      name = remove_quotes($1)
      if self.agent_named(name) 
        "An agent named #{$1} already exists.\n"
      else
        self.agents.add Agent.new(name)
        "Agent #{$1} added.\n"
      end
    when inp =~ /^\s*remove\s*agent\s+(\w+)\s*$/
      name = remove_quotes($1)
      ag = self.agent_named(name) 
      if ag
        self.agents.delete ag
        "Agent #{$1} removed.\n"
      else
        "There is no agent named #{$1}.\n"
      end
    when inp =~ /^\s*new\s*game\s*$/
      self.reset
      self.agents.add Agent.new("Ann")
      self.agents.add Agent.new("Bob")
      Game.startup
    when (inp =~ /^\s*score\s*of\s+(\w+)on\s+(\w+)\s*$/ || 
          inp =~ /^\s*(\w+)'s\s+score\s+on\s+(\w+)\s*$/) 
      unless scorekeeper = self.agent_named($1)
        "Agent #{$1} not found.  Try: list agents\n"
      else 
        unless other = self.agent_named($2)
          "Agent #{$2} not found.  Try: list agents\n"
        else
          self.score(scorekeeper, other)   
        end
      end
    when inp =~ /^\s*score\s*$/
        self.score_all
    when inp =~ /^\s*(\w+)\s+asserts:?\s*([^\.]+)\.?\s*$/ 
      sentence = remove_quotes($2)
      ag = self.agent_named($1)
      unless ag
        "Agent #{$1} not found. Try: list agents\n"
      else
        ag.asserts sentence
        self.score_all
      end
    when inp =~ /^\s*(\w+)\s+disavows:?\s*([^\.]+)\.?\s*$/ 
      sentence = remove_quotes($2)
      ag = self.agent_named($1)
      unless ag
        "Agent #{$1} not found. Try: list agents\n"
      else
        unless ag.commitments_avowed.member? sentence
          "Agent #{$1} has not asserted \"#{sentence}\"\n"
        else
          ag.disavows sentence
          self.score_all
        end
      end
    when inp =~ /^\s*(\w+)\s+challenges\s+(\w+)('s\s+entitlement\s+to)?\s+([^\.]+)\.?\s*$/
      sentence = remove_quotes($4)
      ag = self.agent_named(remove_quotes($1))
      target = self.agent_named(remove_quotes($2))
      unless ag
        return "Agent #{$1} not found. Try: list agents\n"
      else
        unless target
          "Agent #{$2} not found. Try: list agents\n"
        else
          unless target.commitments_avowed.member? sentence
            "#{target.name} never asserted \"#{sentence}\"\n"
          else
            ag.challenges_issued.add(Challenge.new(target, sentence))
            self.score_all
          end
        end
      end
    when inp =~ /^\s*(\w+)\s+(abandons|withdraws)\s+(his\s+|her\s+|its\s+)?challenge\s+(to\s+)?(\w+)('s entitlement to)?\s+([^\.]+)\.?\s*$/
      sentence = remove_quotes($7)
      ag = self.agent_named(remove_quotes($1))
      target = self.agent_named(remove_quotes($5))
      unless ag
        "Agent #{$1} not found. Try: list agents\n"
      else
        unless target
          "Agent #{$5} not found. Try: list agents\n"
        else
          ag.withdraws_challenge(target, sentence)
          self.score_all
        end
      end
    when inp =~ /^\s*(\w+)\s+(adds|removes)\s+(committive|permissive)\s+inference:?\s+(\[|\{)?\s*([^\]\}]+)\s*(\]|\})?\s*\|-\s*([^\.]+)\.?\s*$/
      ag = self.agent_named($1)
      unless ag
        "Agent #{$1} not found. Try: list agents\n"
      else
        prems = $5.strip
        conc = $7.strip
        type = $3
        which = $2
        premises = prems.split(/\s*,\s*|\s*;\s*/)
        inf = Inference.new(premises, conc)
        if type == "permissive"
          if which == "adds"
            ag.permissive_inferences.add inf
          else
            ag.permissive_inferences.delete inf
          end
        else  # committive
          if which == "adds"
            ag.committive_inferences.add inf
          else
            ag.committive_inferences.delete inf
          end
        end
        self.score_all
      end
    when inp =~ /^\s*(\w+)\s+(adds|removes)\s+incompatibility:?\s+(\[|\{)?\s*([^\]\}]+)\s*(\]|\})?\s*\.?\s*$/
      ag = self.agent_named($1)
      unless ag
        "Agent #{$1} not found. Try: list agents\n"
      else
        which = $2
        sents = $4.split(/\s*,\s*|\s*;\s*/)
        incomps = EqSet.new(sents)
        if which == "adds"
          ag.incompatibilities.add incomps
        else # removes
          ag.incompatibilities.delete incomps
        end
        self.score_all
      end
    when inp =~ /^\s*(\w+)\s*$/
      ag = self.agent_named($1)
      if ag
        ag.to_s + "\n" + self.score(ag, ag)
      else
        "Command not recognized.  Try: help\n"
      end
    when true 
      "Comand not recognized.  Try: help\n"
    end
    self.transcript << [inp, result]
    result
  end
    
end  

def testgame  
  # returns test game
  game = Game.new
  game.agents.add Agent.new("Ann")
  game.agents.add Agent.new("Bob")
  game
end

def remove_quotes string
  string.gsub('"', '')
end

def help_message
  "\nlist agents\nadd agent Sal\nremove agent Bob\nnew game\nscore\nBob's score on Ann\nBob asserts A is red\nBob disavows A is red\nAnn challenges Bob's entitlement to A is red\nAnn abandons his challenge to Bob's entitlement to A is red\nBob adds committive inference: A is red; A is small |- A is dangerous\nBob adds incompatibility: {A is red; A is yellow}\nAnn removes incompatibility: {A is blue; A is red}\nAnn removes permissive inference: A is small; A is blue |- A is edible\nAnn\nhelp\nquit\n\n"
end

class GogarServlet < HTTPServlet::AbstractServlet

  @@nextsession, @@games = 
    begin
      Marshal.load(CGI.unescape(File.read("gogar.data")))
    rescue
      [0, {}]
    end
  
  def self.newsession
    self.savesessions
    @@nextsession += 1
    return @@nextsession
  end

  def self.savesessions
    File.new("gogar.data", 'w').print(CGI.escape(Marshal.dump([@@nextsession, @@games])))
  end
  
  def template
    ERB.new %q{
<html>
  <head>
    <title>GOGAR</title>
    <link href="gogar.css" media="all" rel="Stylesheet" type="text/css" />
  </head>
  <body>
    <form action="/" method="post">
      <p><label for="command">Command</label><br/>
      <input type="text" name="command" size="40"/></p>
    </form>
    <pre><%= answer %>
    </pre>
    <a href="/?transcript">Full transcript of session</a>
  </body>
</html>}, 0, "%<>"
  end

  def transcript_template
    ERB.new %q{
<html>
  <head>
    <title>GOGAR Transcript</title>
  </head>
  <body>
    <h2>Transcript</h2>
    <a href="/">Back to GOGAR</a>
    <pre><% transcript.each do |item| %>
<% command = item[0] %>
<% answer = item[1] %>
<b><%= command %></b>

<%= answer %>
<% end %>
</pre>
  </body>
</html> }, 0, "%<>"
  end
  
  def do_GET(req, res)
    cookie = req.cookies.find {|c| c.name == 'gogar'}
    if cookie && @@games[cookie.value.to_i]
      session = cookie.value.to_i
      answer = "Welcome back!  You can start where you left off,
or start a new game by typing 'new game'\n"
    else
      session = GogarServlet.newsession
      @@games[session] = testgame
      res.cookies.push([Cookie.new('gogar', session.to_s)])
      answer = Game.startup
    end
    game = @@games[session]
    res['Content-Type'] = "text/html"
    res.status = 200
    if req.query['transcript']
      page = transcript_template
      transcript = game.transcript
    else
      page = template
    end
    res.body = page.result(binding)
  end

  def do_POST(req, res)
    cookie = req.cookies.find {|c| c.name == 'gogar'}
    if cookie && @@games[cookie.value.to_i]
      session = cookie.value.to_i
    else
      session = GogarServlet.newsession
      @@games[session] = testgame
      res.cookies.push([Cookie.new('gogar', session.to_s)])
    end
    game = @@games[session]
    command = req.query['command'] || "" 
    res['Content-Type'] = "text/html"
    res.status = 200
    answer = game.command(command)
    res.body = template.result(binding)
  end
end 
  
# main loop

if __FILE__ == $0

  require 'optparse'

  options = {}
  opts = OptionParser.new do |opts|
    opts.program_name = 'GOGAR (c) 2006 John MacFarlane'
    opts.version = 'version 1.0'
    opts.banner = "GOGAR -- the game of giving and asking for reasons
Usage:  ruby gogar.rb [options]"
    opts.on("-w", "--web [PORT]", Integer,
            "Run web version of GOGAR [on port PORT]") do |port|
      options[:port] = port || 9094
    end
    opts.on("-v", "--version", "Show version") do
      puts opts.ver
      exit 0
    end
  end

  begin
    opts.parse!
  rescue OptionParser::ParseError => e
    puts e.message
    puts opts.help
    exit 1
  end

  if options[:port] # web version
    puts "Starting web version of GOGAR on http://localhost:#{options[:port]}"
    puts "Type Ctrl-C to stop."

    s = HTTPServer.new(:Port => options[:port])

    s.mount("", GogarServlet)
    trap("INT") { GogarServlet.savesessions; s.shutdown }
    s.start
  
  else  # console version
    begin
      require 'readline'
      with_readline = true
    rescue LoadError
      with_readline = false
    end

    game = Game.new
    output = nil
    print game.command("new game")
    while output != "Goodbye.\n"
      if with_readline
        com = Readline.readline("GOGAR> ", true).chomp
      else
        print "GOGAR> "
        com = readline.chomp 
      end
      output = game.command(com)
      print output
    end
  end
end

