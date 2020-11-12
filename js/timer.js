AFB.Timer = (options = {}) ->
  delay = options.delay || 1000
  ticks = 0
  time = null
  duration = 0
  last_tick_at = null
  js_timer = null
  callback = options.callback || ->
    true

  duration_in_secs = ->
    duration / 1000

  tick = ->
    duration += Date.now() - last_tick_at
    last_tick_at = Date.now()
    callback({duration: duration_in_secs(), ticks: ticks})
    ticks += 1
    js_timer = setTimeout tick, delay

  stop = ->
    clearTimeout js_timer if js_timer
    true

  stop_gracefully = (status, type, id) ->
    AFB.TimeLog.graceful_log(status, type, id, duration_in_secs())
    clearTimeout js_timer if js_timer
    true

  start = ->
    time = time || Date.now()
    last_tick_at = Date.now()
    tick()
    true

  reset = ->
    stop()
    ticks = 0
    time = null
    duration = 0
    js_timer = null
    true

  get_instance = ->
    instance

  get_ticks: ->
    ticks
  get_duration: ->
    duration_in_secs()
  start: ->
    start()
  stop: ->
    stop()
  reset: ->
    reset()
  stop_gracefully: (status, type, id) ->
    stop_gracefully(status, type, id)
