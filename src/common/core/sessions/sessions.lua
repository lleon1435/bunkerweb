local class = require "middleclass"
local plugin = require "bunkerweb.plugin"
local session = require "resty.session"
local utils = require "bunkerweb.utils"

local sessions = class("sessions", plugin)

local ngx = ngx
local ERR = ngx.ERR
local get_variable = utils.get_variable
local session_init = session.init
local tonumber = tonumber

function sessions:initialize(ctx)
	-- Call parent initialize
	plugin.initialize(self, "sessions", ctx)
	-- Check if random cookie name and secrets are already generated
	local is_random = {
		"SESSIONS_SECRET",
		"SESSIONS_NAME",
	}
	self.randoms = {}
	for _, var in ipairs(is_random) do
		if self.variables[var] == "random" then
			local data, _ = self.datastore:get("storage_sessions_" .. var)
			if data then
				self.randoms[var] = data
			end
		end
	end
end

function sessions:set()
	if self.is_loading or self.kind ~= "http" then
		return self:ret(true, "set not needed")
	end
	local checks = {
		["IP"] = self.ctx.bw.remote_addr,
		["USER_AGENT"] = self.ctx.bw.http_user_agent or "",
	}
	self.ctx.bw.sessions_checks = {}
	for check, value in pairs(checks) do
		if self.variables["SESSIONS_CHECK_" .. check] == "yes" then
			table.insert(self.ctx.bw.sessions_checks, { check, value })
		end
	end
	return self:ret(true, "success")
end

function sessions:init()
	if self.is_loading or self.kind ~= "http" then
		return self:ret(true, "init not needed")
	end
	-- Get redis vars
	local redis_vars = {
		["USE_REDIS"] = "",
		["REDIS_HOST"] = "",
		["REDIS_PORT"] = "",
		["REDIS_DATABASE"] = "",
		["REDIS_SSL"] = "",
		["REDIS_TIMEOUT"] = "",
		["REDIS_KEEPALIVE_IDLE"] = "",
		["REDIS_KEEPALIVE_POOL"] = "",
		["REDIS_USERNAME"] = "",
		["REDIS_PASSWORD"] = "",
		["REDIS_SENTINEL_HOSTS"] = "",
		["REDIS_SENTINEL_USERNAME"] = "",
		["REDIS_SENTINEL_PASSWORD"] = "",
		["REDIS_SENTINEL_MASTER"] = "",
	}
	for k, _ in pairs(redis_vars) do
		local value, err = get_variable(k, false)
		if value == nil then
			return self:ret(false, "can't get " .. k .. " variable : " .. err)
		end
		if value == "" then
			redis_vars[k] = nil
		else
			redis_vars[k] = value
		end
	end
	-- Init configuration
	local config = {
		secret = self.variables["SESSIONS_SECRET"],
		cookie_name = self.variables["SESSIONS_NAME"],
		idling_timeout = tonumber(self.variables["SESSIONS_IDLING_TIMEOUT"]),
		rolling_timeout = tonumber(self.variables["SESSIONS_ROLLING_TIMEOUT"]),
		absolute_timeout = tonumber(self.variables["SESSIONS_ABSOLUTE_TIMEOUT"]),
	}
	if self.variables["SESSIONS_SECRET"] == "random" then
		if self.randoms["SESSIONS_SECRET"] then
			config.secret = self.randoms["SESSIONS_SECRET"]
		else
			config.secret = utils.rand(16)
			local ok, err = self.datastore:set("storage_sessions_SESSIONS_SECRET", config.secret)
			if not ok then
				self.logger:log(ERR, "error from datastore:set : " .. err)
			end
		end
	end
	if self.variables["SESSIONS_NAME"] == "random" then
		if self.randoms["SESSIONS_NAME"] then
			config.cookie_name = self.randoms["SESSIONS_NAME"]
		else
			config.cookie_name = utils.rand(16)
			local ok, err = self.datastore:set("storage_sessions_SESSIONS_NAME", config.cookie_name)
			if not ok then
				self.logger:log(ERR, "error from datastore:set : " .. err)
			end
		end
	end
	if redis_vars["USE_REDIS"] ~= "yes" then
		config.storage = "cookie"
	else
		config.storage = "redis"
		config.redis = {
			prefix = "sessions_",
			username = redis_vars["REDIS_USERNAME"],
			password = redis_vars["REDIS_PASSWORD"],
			connect_timeout = tonumber(redis_vars["REDIS_TIMEOUT"]),
			send_timeout = tonumber(redis_vars["REDIS_TIMEOUT"]),
			read_timeout = tonumber(redis_vars["REDIS_TIMEOUT"]),
			keepalive_timeout = tonumber(redis_vars["REDIS_KEEPALIVE_IDLE"]),
			pool = "bw-redis",
			pool_size = tonumber(redis_vars["REDIS_KEEPALIVE_POOL"]),
			ssl = redis_vars["REDIS_SSL"] == "yes",
			database = tonumber(redis_vars["REDIS_DATABASE"]),
		}
		if redis_vars["REDIS_SENTINEL_HOSTS"] ~= nil then
			config.redis.master = redis_vars["REDIS_SENTINEL_MASTER"]
			config.redis.role = "master"
			config.redis.sentinel_username = redis_vars["REDIS_SENTINEL_USERNAME"]
			config.redis.sentinel_password = redis_vars["REDIS_SENTINEL_PASSWORD"]
			config.redis.sentinels = {}
			for sentinel_host in redis_vars["REDIS_SENTINEL_HOSTS"]:gmatch("%S+") do
				local shost, sport = sentinel_host:match("([^:]+):?(%d*)")
				if sport == "" then
					sport = 26379
				else
					sport = tonumber(sport)
				end
				table.insert(config.redis.sentinels, { host = shost, port = sport })
			end
		else
			config.redis.host = redis_vars["REDIS_HOST"]
			config.redis.port = tonumber(redis_vars["REDIS_PORT"])
		end
	end
	session_init(config)
	return self:ret(true, "sessions init successful")
end

return sessions
