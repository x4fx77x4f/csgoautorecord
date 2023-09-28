#!/usr/bin/env luajit

local argparse = require("argparse")
local parser = argparse("./init.lua", "Connect to CS:GO and CS2 RCON servers.")
parser:option("--password", "RCON password."):args(1)
parser:flag("--verbose", "Output extra info.")
parser:flag("--csgo")
parser:command_target("command")
local autorecord = parser:command("autorecord")
autorecord:option("--path", "Path to 'csgo/'.")
autorecord:flag("--gzip", "Compress demos with gzip.")
local console = parser:command("console")
local args = parser:parse()
if args.path ~= nil then
	assert(string.find(args.path, "[^%w_/ -]") == nil)
elseif args.gzip then
	parser:error("you must specify path to compress demos")
end
local function printf(...)
	return assert(io.stdout:write(string.format(...)))
end
local printf_verbose
if args.verbose then
	printf_verbose = printf
else
	function printf_verbose() end
end
io.stdout:setvbuf("no")

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
	printf_verbose("sent: size: %s, id: 0x%8x, type: %d, body: %q\n", #body+10, id, packet_type, body)
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
	printf_verbose("received: ")
	local size = unpack_uint32_le(assert(client:receive(4)))
	printf_verbose("size: %u, ", size)
	assert(size >= 10)
	--assert(size <= 4096) -- the wiki is wrong. highest value i've seen is 4105
	local id = unpack_uint32_le(assert(client:receive(4)))
	printf_verbose("id: 0x%8x, ", id)
	local packet_type = unpack_uint32_le(assert(client:receive(4)))
	printf_verbose("type: %u, ", packet_type)
	local body = assert(client:receive(size-4-4-1-1))
	printf_verbose("body: %q", body)
	assert(client:receive(2) == "\x00\x00")
	printf_verbose("\n")
	return size, id, packet_type, body
end
local SERVERDATA_AUTH = 3
local SERVERDATA_EXECCOMMAND = 2
local SERVERDATA_AUTH_RESPONSE = 2
local SERVERDATA_RESPONSE_VALUE = 0
local function execcommand(client, command)
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
			if args.csgo then
				assert(body == "")
				size, id, packet_type, body = receive_rcon(client)
			end
			assert(id == response_id)
			assert(packet_type == SERVERDATA_RESPONSE_VALUE)
			assert(body == "\x00\x01\x00\x00")
			break
		else
			error("unexpected packet")
		end
	end
	retval = table.concat(retval)
	return retval
end

local socket = require("socket")
local client = socket.tcp()
assert(client:connect("127.0.0.1", 27015))

local auth_id = send_rcon(client, SERVERDATA_AUTH, args.password)
local size, id, packet_type, body = receive_rcon(client)
if id == auth_id and packet_type == SERVERDATA_RESPONSE_VALUE and body == "" then
	printf_verbose("ignoring packet\n")
	size, id, packet_type, body = receive_rcon(client)
end
assert(packet_type == SERVERDATA_AUTH_RESPONSE)
if id == 0xffffffff then
	error("authentication failed")
elseif id == auth_id then
	printf("authentication success\n")
else
	error("unexpected packet")
end

local command = args.command
if command == "console" then
	while true do
		io.write("] ")
		local command = io.read("*l")
		if command == nil then
			io.write("\n")
			break
		end
		local retval = execcommand(client, command)
		print(retval)
	end
elseif command == "autorecord" then
	local demo_path
	local function exists(path)
		local handle = io.open(path, "rb")
		if handle == nil then
			return false
		end
		handle:close()
		return true
	end
	local function demo_path_to_path(demo_path)
		return string.format("%s/%s.dem", args.path, demo_path)
	end
	local function compress(path)
		local command = string.format("gzip \"%s\"", path)
		printf_verbose("compressing demo with %q", command)
		local code = os.execute(command)
		if code ~= 0 then
			print("WARN: error when compressing demo")
		end
	end
	while true do
		local retval = execcommand(client, "net_status")
		local connections = tonumber(retval:match("^Net status for host 127%.0%.0%.1:\n%- Config: Multiplayer, listen, (%d+) connections\n"))
		if connections == nil then
			print_warn_verbose("WARN: unexpected response when trying to get status", retval)
		elseif demo_path == nil and connections > 0 then
			demo_path = os.date("!demos/%Y-%m-%d_%H-%M-%S")
			printf("connected; recording %q\n", demo_path)
		elseif demo_path ~= nil and connections == 0 then
			printf("disconnected; recorded %q\n", demo_path)
			if args.gzip then
				compress(demo_path_to_path(demo_path))
				local i = 2
				while true do
					local path = demo_path_to_path(string.format("%s_%d", demo_path, i))
					if not exists(path) then
						break
					end
					compress(path)
					i = i+1
				end
			end
			demo_path = nil
		end
		if demo_path ~= nil then
			retval = execcommand(client, "record \""..demo_path.."\"")
			if retval:match("^Recording to (.*)%.dem%.%.%.\n$") == demo_path then
				printf("started recording %q\n", demo_path)
			elseif retval == "Please start demo recording after current round is over.\n" then
				printf_verbose("can't record yet\n")
			elseif retval ~= "Already recording.\n" and retval ~= "" then
				printf_verbose("WARN: unexpected response when trying to start recording: %q\n", retval)
			end
		end
		socket.sleep(1)
	end
end
printf_verbose("disconnecting\n")
client:close()
