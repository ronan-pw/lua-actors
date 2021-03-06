local Actors = { mt = {} }
local lanes = require "lanes".configure()
local actor_mt = { __index = mt }
local MESSAGE_KEY = true
local ADD_ACTOR_KEY = false
local current_actor

local top_level_actor = { id = 0, linda = lanes.linda() }
setmetatable(top_level_actor, { __index = Actors.mt })

function Actors.mt.tell(to, msg)
  to.linda:send(MESSAGE_KEY, { body = msg, to = to.id, from = current_actor or top_level_actor })
end

function Actors.mt.ask(to, msg, timeout)
  local from = current_actor or top_level_actor
  to:tell(msg)
  local key, reply = top_level_actor.linda:receive(timeout, MESSAGE_KEY)
  if reply then
    return reply.body
  end
  return nil
end

function Actors.system(num_threads, libs)
  local system = {}
  local num_actors = 0
  local actor_lanes = {}
  local lindas = {}
  local pingers = {}

  local function process(linda)
    local actor_states = {}
    while true do
      key, msg = linda:receive(1, ADD_ACTOR_KEY, MESSAGE_KEY)
      if key == ADD_ACTOR_KEY then
        actor_states[msg.id] = { state = msg.state, receive = msg.receive }
      elseif key == MESSAGE_KEY then
        local dest = actor_states[msg.to]        
        if dest ~= nil then
          current_actor = dest
          dest.receive(dest.state, msg.body, msg.from)
          current_actor = nil
        end
      end
    end
  end

  local function new_actor(receive, state, linda)
    num_actors = num_actors + 1
    local actor = {
      id = num_actors,
      linda = linda
    }
    linda:send(ADD_ACTOR_KEY, { id = num_actors, state = state or {}, receive = receive })
    setmetatable(actor, { __index = Actors.mt })
    return actor
  end

  function system.actor(receive, state)
    return new_actor(receive, state, lindas[math.random(#lindas)])
  end

  function system.robust_actor(receive, state, on_err)
    system.actor(function(state, body, from)
      local success, err = pcall(receive)
      if not success then
        on_err(state, body, from, err)
      end
    end)
  end

  libs = libs or "*"

  for i = 1, num_threads do
    actor_lanes[i] = lanes.gen(libs, process)
    local linda = lanes.linda()
    lindas[i] = linda
    actor_lanes[i](linda)
    pingers[i] = new_actor(receive, {}, linda)
  end

  return system
end

return Actors