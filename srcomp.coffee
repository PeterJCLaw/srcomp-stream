rq = require 'request'
_ = require 'underscore'
moment = require 'moment'
Bacon = require 'baconjs'
configuration = require './config'


checkedRequest = (url, cb) ->
  rq url, (error, response, body) =>
    if error
      console.error "Error making request to '#{url}': #{error}"
      return

    unless response.statusCode is 200
      console.error "Invalid status code from '#{url}': #{response.statusCode}"
      return

    return cb(response, body)


class SRComp
  constructor: (@base) ->
    @events = new Bacon.Bus()
    @teams = {}
    @matches = []
    @currentDelay = 0
    @currentMatch = []
    @currentStagingMatches = []
    @currentShepherdingMatches = []
    @lastScoredMatch = null
    @koRounds = null
    @koStructure = null
    @tiebreaker = null
    do @queryConfig

  queryConfig: ->
    configInterval = null

    loadConfig = () =>
      checkedRequest "#{@base}/config", (response, body) =>
        # Avoid double configuration
        return unless configInterval
        clearInterval configInterval
        configInterval = null

        @config = JSON.parse(body)['config']
        console.log @config
        do @queryState
        setInterval (=> do @sendPing), @config['ping_period'] * 1000
        setInterval (=> do @queryState), 500
        setInterval (=> do @updateCurrent), 2000

    configInterval = setInterval (=> do loadConfig), 300

  queryState: ->
    checkedRequest "#{@base}/state", (response, body) =>
      newState = JSON.parse(body)['state']
      if newState isnt @savedState
        @savedState = newState
        do @reloadData

  reloadData: ->
    console.log "Reloading data"
    do @reloadTeams
    do @reloadMatches
    do @reloadLastScoredMatch
    do @reloadKnockouts
    do @reloadTiebreaker

  seedRecords: ->
    @seedTeamRecords().concat(@seedMatchRecord())
                      .concat(@seedCurrentStagingMatchesRecord())
                      .concat(@seedCurrentShepherdingMatchesRecord())
                      .concat(@seedScoredMatchRecord())
                      .concat(@seedKnockoutsRecord())
                      .concat(@seedKnockoutStructureRecord())
                      .concat(@seedDelayRecord())
                      .concat(@seedTiebreakerRecord())

  seedTeamRecords: ->
    for team, record of @teams
      event: 'team'
      data: record

  seedDelayRecord: ->
    [{event: 'current-delay', data: @currentDelay}]

  seedMatchRecord: ->
    [{event: 'match', data: @currentMatch}]

  seedCurrentStagingMatchesRecord: ->
    [{event: 'current-staging-matches', data: @currentStagingMatches}]

  seedCurrentShepherdingMatchesRecord: ->
    [{event: 'current-shepherding-matches', data: @currentShepherdingMatches}]

  seedScoredMatchRecord: ->
    return [] if not @lastScoredMatch?
    [{event: 'last-scored-match', data: @lastScoredMatch}]

  seedKnockoutsRecord: ->
    return [] if not @koRounds?
    [{event: 'knockouts', data: @koRounds}]

  seedKnockoutStructureRecord: ->
    return [] if not @koStructure?
    [{event: 'knockout-structure', data: @koStructure}]

  seedTiebreakerRecord: ->
    return [] if not @tiebreaker?
    [{event: 'tiebreaker', data: @tiebreaker}]

  txTeamRecord: (tla, record) ->
    @events.push
      event: 'team'
      data: record

  reloadTeams: ->
    checkedRequest "#{@base}/teams", (response, body) =>
      newTeams = JSON.parse(body)['teams']
      if not _.isEqual(@teams, newTeams)
        # Diffs 1: deleted teams
        for key of _.difference(_.keys(@teams), _.keys(newTeams))
          @txTeamRecord key, null
        # Diffs 2: actual differences
        for key, record of newTeams
          if not _.isEqual(record, @teams[key])
            @txTeamRecord key, record
        @teams = newTeams

  reloadMatches: ->
    checkedRequest "#{@base}/matches", (response, body) =>
      matches = JSON.parse(body)['matches']
      if not _.isEqual(@matches, matches)
        @matches = matches
        do @updateCurrent

  reloadLastScoredMatch: ->
    checkedRequest "#{@base}/matches/last_scored", (response, body) =>
      lastScoredMatch = JSON.parse(body)['last_scored']
      if not _.isEqual(@lastScoredMatch, lastScoredMatch)
        @lastScoredMatch = lastScoredMatch
        @events.push
          event: 'last-scored-match'
          data: @lastScoredMatch

  updateCurrent: ->
    checkedRequest "#{@base}/current", (response, body) =>
      currentInfo = JSON.parse(body)
      newCurrentMatch = currentInfo['matches']
      if not _.isEqual(newCurrentMatch, @currentMatch)
        @currentMatch = newCurrentMatch
        @events.push
          event: 'match'
          data: @currentMatch

      newCurrentStagingMatches = currentInfo['staging_matches']
      if not _.isEqual(newCurrentStagingMatches, @currentStagingMatches)
        @currentStagingMatches = newCurrentStagingMatches
        @events.push
          event: 'current-staging-matches'
          data: @currentStagingMatches

      newCurrentShepherdingMatches = currentInfo['shepherding_matches']
      if not _.isEqual(newCurrentShepherdingMatches, @currentShepherdingMatches)
        @currentShepherdingMatches = newCurrentShepherdingMatches
        @events.push
          event: 'current-shepherding-matches'
          data: @currentShepherdingMatches

      newCurrentDelay = currentInfo['delay']
      if not _.isEqual(newCurrentDelay, @currentDelay)
        @currentDelay = newCurrentDelay
        @events.push
          event: 'current-delay'
          data: @currentDelay

  sendPing: ->
    @events.push
      event: 'ping'
      data: @config['ping_period'] * 1000

  reloadKnockouts: ->
    checkedRequest "#{@base}/knockout", (response, body) =>
      parsedBody = JSON.parse(body)

      newKORounds = parsedBody['rounds']
      if not _.isEqual(@koRounds, newKORounds)
        @koRounds = newKORounds
        @events.push
          event: 'knockouts'
          data: @koRounds

      # Cope with older APIs not having this value -- in which case we don't
      # emit this event. Relies on @koStructure defaulting to `null`.
      newKOStructure = parsedBody['structure'] or null
      if not _.isEqual(@koStructure, newKOStructure)
        @koStructure = newKOStructure
        @events.push
          event: 'knockout-structure'
          data: @koStructure

  reloadTiebreaker: ->
    rq "#{@base}/tiebreaker", (error, response, body) =>
      if error
        console.error error
        return

      newTiebreaker = null
      if response.statusCode is 200
        newTiebreaker = JSON.parse(body)['tiebreaker']

      console.log(@tiebreaker, newTiebreaker)

      if not _.isEqual(@tiebreaker, newTiebreaker)
        @tiebreaker = newTiebreaker
        @events.push
          event: 'tiebreaker'
          data: @tiebreaker


module.exports =
  SRComp: SRComp
