configuration = require "./config"
srcomp = require "./srcomp"
Bacon = require 'baconjs'

sse = require './http-socket'

console.log('Using', configuration)

comp = new srcomp.SRComp(configuration.SRCOMP)

comp.events.onValue (event) ->
  console.log JSON.stringify(event, null, 2) if configuration.DEBUG

sse(comp).listen(configuration.WEB_PORT, '::')
