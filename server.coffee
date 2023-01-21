configuration = require "./config"
srcomp = require "./srcomp"
Bacon = require 'baconjs'

sse = require './http-socket'

console.log('Using', configuration)

comp = new srcomp.SRComp(configuration.SRCOMP)

if configuration.DEBUG
  comp.events.onValue (event) ->
    console.log JSON.stringify(event, null, 2)

sse(comp).listen(configuration.WEB_PORT, '::')
