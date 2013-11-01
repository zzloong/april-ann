package.path = string.format("%s?.lua;%s", string.get_path(arg[0]), package.path)
--
require "master"
require "common"
--
local conf_path = "/etc/APRIL-ANN-MAPREDUCE/master.lua"
local conf,error_msg = common.load_configuration(conf_path)
if not conf then error("Error loading " .. conf_path .. ": "..error_msg) end
--
local MASTER_BIND = conf.bind_address or '*'
local MASTER_PORT = conf.port or 8888
--
local BIND_TIMEOUT      = conf.bind_timeout or 10
local TIMEOUT           = conf.timeout      or 60   -- in seconds
local WORKER_PING_TIMER = conf.ping_timer   or 60   -- in seconds
--

-- function map(key, value) do stuff coroutine.yield(key, value) end
-- function reduce(key, iterator) do stuff return result end

local workers          = {} -- a table with registered workers
local inv_workers      = {} -- the inverted dictionary
-- handler for I/O
local select_handler   = common.select_handler()
local connections      = common.connections_set()
local mastersock       = socket.tcp() -- the main socket
local logger           = common.logger()

---------------------------------------------------------------
---------------------------------------------------------------
---------------------------------------------------------------

local task       = nil
local task_count = 0
function make_task_id(name)
  task_count = task_count+1
  return string.format("%s-%09d",name,task_count)
end

---------------------------------------------------------------
------------------- CONNECTION HANDLER ------------------------
---------------------------------------------------------------

local message_reply = {
  OK   = function() return nil end,
  
  PING = "PONG",
  
  EXIT = "EXIT",
  
  -- A task is defined in a Lua script. This script must be a path to a filename
  -- located in a shared disk between cluster nodes.
  -- TODO: allow to send a Lua code string, instead of a filename path
  TASK = function(conn,msg)
    local name,arg,script = msg:match("^%s*([^%s]+)%s*(return %b{})%s*(.*)")
    local address = conn:getpeername()
    if task ~= nil then
      logger:warningf("The cluster is busy\n")
      return "ERROR"
    end
    local ID = make_task_id(name)
    task = master.task(logger, select_handler, conn, ID, script, arg, MASTER_PORT)
    if not task then return "ERROR" end
    logger:printf("Running TASK %s executed by client %s at %s\n",
		  ID, name, address)
    return ID
  end,

  WORKER =
    function(conn,msg)
      local name,port,nump,mem = table.unpack(string.tokenize(msg or ""))
      local address = conn:getpeername()
      logger:print("Received WORKER action:", address, name, port, nump, mem)
      local w = inv_workers[name]
      if w then
	logger:print("Updating WORKER")
	w:update(address,port,nump,mem)
      else
	logger:print("Creating WORKER")
	local w = master.worker(name,address,port,nump,mem)
	table.insert(workers, w)
	inv_workers[name] = workers[#workers]
	w:ping(select_handler)
      end
      return "OK"
    end,

  MAP_RESULT = function(conn,msg)
    if not task then return "OK" end
    local map_key,map_result,error_msg = msg:match("^%s*(%b{})%s*(return .*)$")
    local address = conn:getpeername()
    map_key,error_msg = common.load(string.sub(map_key,2,#map_key-1),logger)
    if not map_key then
      logger:debug("Error in MAP_RESULT action: ", error_msg)
      task:throw_error(string.format("MAP_RESULT %s", error_msg))
      return "ERROR"
    else
      logger:debug("Received MAP_RESULT action: ", address, map_key)
      -- TODO: throw error if result is not well formed??
      local ok = task:process_map_result(map_key,map_result)
      -- TODO: throw error
      -- if not ok then return "ERROR" end
      return "OK"
    end
  end,

  REDUCE_RESULT = function(conn,msg)
    if not task then return "OK" end
    local key_and_value = msg:match("^%s*(return .*)$")
    local key,value = common.load(key_and_value,logger)
    -- TODO: throw error if result is not well formed??
    local ok = task:process_reduce_result(key,value)
    -- TODO: throw error
    -- if not ok then return "ERROR" end
    return "OK"
  end,

  KEY_VALUE_ERROR = function(conn,msg)
    local where,error_msg = msg:match("^%s*([^%s]+)%s*(.*)$")
    task:throw_error(msg)
    return "ERROR"
  end,

  RUNTIME_ERROR = function(conn,msg)
    local where,error_msg = msg:match("^%s*([^%s]+)%s*(.*)$")
    task:throw_error(msg)
    return "ERROR"
  end,

}

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

function check_workers(t, inv_t)
  local dead_workers = iterator(ipairs(t)):
  -- filter the dead ones
  filter(function(i,w) return w:dead() end):
  -- take the index
  table(function(IDX,i,w) return IDX,i end)
  --
  -- removes dead workers
  for i=#dead_workers,1,-1 do
    local p = dead_workers[i]
    local name = t[p]:get_name()
    logger:print("Removing dead WORKER: ", name)
    table.remove(t,p)
    inv_t[name] = nil
    if task then task:throw_error("WORKER " .. name .. " is dead") end
  end
end

function master_func(mastersock,conn)
  if conn then
    local a,b = conn:getsockname()
    local c,d = conn:getpeername()
    logger:debugf("Connection received at %s:%d from %s:%d\n",a,b,c,d)
    connections:add(conn)
    select_handler:receive(conn,
			   common.make_connection_handler(select_handler,
							  message_reply,
							  connections))
  end
  -- following instruction allows action chains
  select_handler:accept(mastersock, master_func)
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

function main()
  logger:printf("Running master binded to %s:%s\n", MASTER_BIND, MASTER_PORT)
  
  local ok,msg = mastersock:bind(MASTER_BIND, MASTER_PORT)
  while not ok do
    logger:warningf("ERROR: %s\n", msg)
    util.sleep(BIND_TIMEOUT)
    ok,msg = mastersock:bind(MASTER_BIND, MASTER_PORT)
  end
  ok,msg = mastersock:listen()
  if not ok then error(msg) end
  
  -- register SIGINT handler for safe master stop
  signal.register(signal.SIGINT,
		  function()
		    logger:raw_print("\n# Closing master")
		    connections:close()
		    if master then mastersock:close() mastersock = nil end
		    collectgarbage("collect")
		    os.exit(0)
		  end)
  
  logger:print("Ok")
  
  -- appends accept
  select_handler:accept(mastersock, master_func)

  local clock = util.stopwatch()
  clock:go()
  while true do
    local cpu,wall = clock:read()
    if wall > WORKER_PING_TIMER then
      collectgarbage("collect")
      --
      iterator(ipairs(workers)):
      select(2):
      filter(function(w)return not w:dead() end):
      apply(function(w) w:ping(select_handler) end)
      --
      check_workers(workers, inv_workers)
      clock:stop()
      clock:reset()
      clock:go()
    end
    -- print(task and task:get_state())
    if task then
      local state = task:get_state()
      if state == "ERROR" then
	task:send_error_message(select_handler, workers)
	task = nil
	collectgarbage("collect")
      elseif state == "STOPPED" then
	if #workers > 0 then
	  -- TODO: throw an error
	  task:prepare_map_plan(workers)
	end
      elseif state == "PREPARED" then
	logger:print("MAP",task:get_id())
	task:do_map(workers)
      elseif state == "MAP_FINISHED" then
	logger:print("REDUCE",task:get_id())
	task:do_reduce(workers)
      elseif state == "REDUCE_FINISHED" then
	logger:print("SEQUENTIAL AND SHARE",task:get_id())
	task:do_sequential(workers)
      elseif state == "SEQUENTIAL_FINISHED" then
	logger:print("LOOP",task:get_id())
	task:do_loop()
      elseif state == "FINISHED" then
	logger:print("FINISHED",task:get_id())
	task = nil
	collectgarbage("collect")
      elseif state ~= "MAP" and state ~= "REDUCE" and state ~= "SEQUENTIAL" and state ~= "LOOP" then
	logger:warningf("Unknown task state: %s\n", state)
      end
    end
    select_handler:execute(TIMEOUT)
    connections:remove_dead_conections()
  end
end

------------------------------------------------------------------------------

main()