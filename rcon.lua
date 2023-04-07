#!/usr/bin/env luajit
-- https://developer.valvesoftware.com/wiki/Source_RCON_Protocol
local socket = require("socket")
local client = socket.tcp()
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
local function send_rcon(client, packet_type, body, id)
	if id == nil then
		id = math.random(0, 2^32-1)
	end
	if body == nil then
		body = ""
	end
	local size = #body+10
	assert(client:send(
		pack_uint32_le(size)
		..pack_uint32_le(id)
		..pack_uint32_le(packet_type)
		..body.."\x00"
		.."\x00"
	))
	return id, packet_type, size, body
end
local SERVERDATA_AUTH = 3
local SERVERDATA_EXECCOMMAND = 2
local SERVERDATA_AUTH_RESPONSE = 2
local SERVERDATA_RESPONSE_VALUE = 0
local function frombit(n)
	if n < 0 then
		return 2^32+n
	end
	return n
end
local function unpack_uint32_le(data)
	assert(#data == 4)
	local b1, b2, b3, b4 = string.byte(data, 1, 4)
	return frombit(bit.bor(
		bit.lshift(b4, 24),
		bit.lshift(b3, 16),
		bit.lshift(b2, 8),
		b1
	))
end
local function receive_rcon(client)
	local size = unpack_uint32_le(assert(client:receive(4)))
	assert(size >= 10)
	--assert(size <= 4096) -- the wiki is wrong. highest value i've seen is 4105
	local id = unpack_uint32_le(assert(client:receive(4)))
	local packet_type = unpack_uint32_le(assert(client:receive(4)))
	local body = assert(client:receive(size-4-4-1-1))
	assert(client:receive(2) == "\x00\x00")
	return size, id, packet_type, body
end
local function nice_size(n)
	if n < 1000 then
		return string.format("%d B", n)
	end
	n = n/1000
	if n < 1000 then
		return string.format("%d kB", math.floor(n+0.5))
	end
	n = n/1000
	if n < 1000 then
		return string.format("%d MB", math.floor(n+0.5))
	end
	n = n/1000
	return string.format("%d GB", math.floor(n+0.5))
end
local function send_rcon_verbose(client, packet_type, body, id)
	if id == nil then
		id = math.random(0, 2^32-1)
	end
	if body == nil then
		body = ""
	end
	print(string.format("sent: size: %s, id: 0x%8x, type: %d, body: %q", #body+10, id, packet_type, body))
	return send_rcon(client, packet_type, body, id)
end
local function read_rcon_verbose(client)
	local size, id, packet_type, body = receive_rcon(client)
	print(string.format("received: size: %s, id: 0x%8x, type: %d, body: %q", size, id, packet_type, body))
	return size, id, packet_type, body
end
assert(client:connect("127.0.0.1", 27015))
local auth_id = send_rcon_verbose(client, SERVERDATA_AUTH, "knDz16xdGXIz57uCIbtt8J3dxe8AXwiZKZYvRW0W301F0pUZyu")
while true do
	
	local size, id, packet_type, body = read_rcon_verbose(client)
	if packet_type == SERVERDATA_AUTH_RESPONSE then
		if id == 0xffffffff then
			error("authentication failed")
		elseif id == auth_id then
			print("authentication success")
			send_rcon_verbose(client, SERVERDATA_EXECCOMMAND, "version")
			send_rcon_verbose(client, SERVERDATA_RESPONSE_VALUE, "")
		end
	end
end