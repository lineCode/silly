local fifo = require "socketdispatch"

local tinsert = table.insert
local tunpack = table.unpack
local tconcat = table.concat

local redis = {}

local response_header = {}

local header = "+-:*$"

response_header[header:byte(1)] = function (sfifo, res)        --'+'
	return true, true, res
end

response_header[header:byte(2)] = function (sfifo, res)        --'-'
	return true, false, res
end

response_header[header:byte(3)] = function (sfifo, res)        --':'
	return true, true, tonumber(res)
end

response_header[header:byte(5)] = function (sfifo, res)        --'$'
	local nr = tonumber(res)
	if nr == -1 then
		return true, false, nil
	end

	local param = sfifo:read(nr + 2)
	if param == nil then
		return false
	end
	return true, true, string.sub(param, 1, -3)
end


local function read_response(sfifo)
	local data = sfifo:readline("\r\n")
	if data == nil then
		return false
	end

	local head = data:byte(1)
	local func = response_header[head]
	local res = data
	if func then
		res = string.sub(res, 2)
	else
		res = string.sub(res, 1, #res - 2)
		func = response_header.data
	end
	return func(sfifo, res)
end

response_header[header:byte(4)] = function (sfifo, res)        --'*'
	local cmd_success = true
	local cmd_res = {}
	local nr = tonumber(res)
	for i = 1, nr do
		local ok, success, data = read_response(sfifo)
		if ok == false then
			return false
		end
		cmd_success = cmd_success and success
		tinsert(cmd_res, data)
	end

	if #cmd_res == 1 then
		return true, cmd_success, tunpack(cmd_res)
	else
		return true, cmd_success, cmd_res
	end
end

local function request(self, cmd)
	return self.sfifo:request(cmd, read_response)
end

local function pack_param(lines, param)
	local p =  tostring(param)
	tinsert(lines, string.format("$%d", #p))
	tinsert(lines, p)
end

local function pack_cmd(cmd, param)
	local pn = 1
	if param ~= nil then
		assert(type(param) == "table")
		pn = pn + #param;
	end
	local lines = {string.format("*%d", pn), }
	pack_param(lines, cmd)
	for _, v in ipairs (param) do
		pack_param(lines, v)
	end
	local sz = tconcat(lines, "\r\n")
	return sz .. "\r\n"
end

function redis:connect(config)
	local t = {
		addr = config.addr,
		user = config.user,
		passwd = config.passwd,
		sfifo = fifo:create {
			addr = config.addr,
		},
	}
	setmetatable(t, {__index = self})
	local ret, err = t.sfifo:connect()
	if ret then
		return t
	else
		return nil, err
	end
end

setmetatable(redis, {__index = function (self, k)
	local cmd = string.upper(k)
	local f = function (self, p, ...)
		if type(p) == "table" then
			return request(self, pack_cmd(cmd, p))
		elseif p ~= nil then
			return request(self, pack_cmd(cmd, {p, ...}))
		else
			return request(self, pack_cmd(cmd, {}))
		end
	end

	self[k] = f
	return f
end
})


return redis


