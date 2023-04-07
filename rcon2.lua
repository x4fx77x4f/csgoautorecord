#!/usr/bin/env luajit

local function frombit(n)
	if n < 0 then
		return 2^32+n
	end
	return n
end

local function pack_uint32_le(n)
	assert(n >= 0)
	assert(n <= 2^32-1)
	assert(n == n)
	return string.char(
		bit.band(n, 0xff),
		bit.rshift(bit.band(n, 0xff00), 8),
		bit.rshift(bit.band(n, 0xff0000), 16),
		bit.rshift(bit.band(n, 0xff000000), 24)
	)
end
local function unpack_uint32_le(data)
	assert(#data == 4)
	local b4, b3, b2, b1 = string.byte(data, 1, 4)
	return frombit(bit.bor(
		bit.lshift(b1, 24),
		bit.lshift(b2, 16),
		bit.lshift(b3, 8),
		b4
	))
end

-- https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
local function send_rcon(client, packet_type, body, id)
	if id == nil then
		id = math.random(0, 2^32-1)
	end
	if body == nil then
		body = ""
	end
	local size = #body+10
	print(string.format("sent: size: %s, id: 0x%8x, type: %d, body: %q", #body+10, id, packet_type, body))
	assert(client:send(
		pack_uint32_le(size)
		..pack_uint32_le(id)
		..pack_uint32_le(packet_type)
		..body.."\x00"
		.."\x00"
	))
	return id, packet_type, size, body
end
local function receive_rcon(client)
	local size = unpack_uint32_le(assert(client:receive(4)))
	assert(size >= 10)
	--assert(size <= 4096) -- the wiki is wrong. highest value i've seen is 4105
	local id = unpack_uint32_le(assert(client:receive(4)))
	local packet_type = unpack_uint32_le(assert(client:receive(4)))
	local body = assert(client:receive(size-4-4-1-1))
	assert(client:receive(2) == "\x00\x00")
	print(string.format("received: size: %s, id: 0x%8x, type: %d, body: %q", size, id, packet_type, body))
	return size, id, packet_type, body
end
local SERVERDATA_AUTH = 3
local SERVERDATA_EXECCOMMAND = 2
local SERVERDATA_AUTH_RESPONSE = 2
local SERVERDATA_RESPONSE_VALUE = 0
local function execcommand(client, command)
	--print(string.format("execcommand: %q", command))
	local exec_id = send_rcon(client, SERVERDATA_EXECCOMMAND, command)
	local response_id = send_rcon(client, SERVERDATA_RESPONSE_VALUE, "")
	local retval, i = {}, 0
	while true do
		local size, id, packet_type, body = receive_rcon(client)
		assert(packet_type == SERVERDATA_RESPONSE_VALUE)
		if id == exec_id then
			i = i+1
			retval[i] = body
		elseif id == response_id then
			assert(body == "")
			size, id, packet_type, body = receive_rcon(client)
			assert(id == response_id)
			assert(packet_type == SERVERDATA_RESPONSE_VALUE)
			assert(body == "\x00\x01\x00\x00")
			break
		else
			error("unexpected packet")
		end
	end
	retval = table.concat(retval)
	--print(string.format("response: %q", retval))
	return retval
end

local socket = require("socket")
local client = socket.tcp()
assert(client:connect("127.0.0.1", 27015))

local auth_id = send_rcon(client, SERVERDATA_AUTH, "knDz16xdGXIz57uCIbtt8J3dxe8AXwiZKZYvRW0W301F0pUZyu")
local size, id, packet_type, body = receive_rcon(client)
if id == auth_id and packet_type == SERVERDATA_RESPONSE_VALUE and body == "" then
	print("ignoring packet")
	size, id, packet_type, body = receive_rcon(client)
end
assert(packet_type == SERVERDATA_AUTH_RESPONSE)
if id == 0xffffffff then
	error("authentication failed")
elseif id == auth_id then
	print("authentication success")
else
	error("unexpected packet")
end

execcommand(client, "net_status")
execcommand(client, "status")

client:close()