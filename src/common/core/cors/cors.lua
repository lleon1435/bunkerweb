local class = require "middleclass"
local plugin = require "bunkerweb.plugin"
local utils = require "bunkerweb.utils"

local cors = class("cors", plugin)

local ngx = ngx
local HTTP_NO_CONTENT = ngx.HTTP_NO_CONTENT
local WARN = ngx.WARN
local regex_match = utils.regex_match
local get_deny_status = utils.get_deny_status

function cors:initialize(ctx)
	-- Call parent initialize
	plugin.initialize(self, "cors", ctx)
	self.all_headers = {
		["CORS_EXPOSE_HEADERS"] = "Access-Control-Expose-Headers",
		["CROSS_ORIGIN_OPENER_POLICY"] = "Cross-Origin-Opener-Policy",
		["CROSS_ORIGIN_EMBEDDER_POLICY"] = "Cross-Origin-Embedder-Policy",
		["CROSS_ORIGIN_RESOURCE_POLICY"] = "Cross-Origin-Resource-Policy",
	}
	self.preflight_headers = {
		["CORS_MAX_AGE"] = "Access-Control-Max-Age",
		["CORS_ALLOW_CREDENTIALS"] = "Access-Control-Allow-Credentials",
		["CORS_ALLOW_METHODS"] = "Access-Control-Allow-Methods",
		["CORS_ALLOW_HEADERS"] = "Access-Control-Allow-Headers",
	}
end

function cors:header()
	-- Check if header is needed
	if self.variables["USE_CORS"] ~= "yes" then
		return self:ret(true, "service doesn't use CORS")
	end
	-- Skip if Origin header is not present
	if not self.ctx.bw.http_origin then
		return self:ret(true, "origin header not present")
	end
	-- Always include Vary header to prevent caching
	local ngx_header = ngx.header
	local vary = ngx_header.Vary
	if vary then
		if type(vary) == "string" then
			ngx_header.Vary = { vary, "Origin" }
		else
			table.insert(vary, "Origin")
			ngx_header.Vary = vary
		end
	else
		ngx_header.Vary = "Origin"
	end
	-- Check if Origin is allowed
	if
		self.ctx.bw.http_origin
		and self.variables["CORS_DENY_REQUEST"] == "yes"
		and self.variables["CORS_ALLOW_ORIGIN"] ~= "*"
		and not regex_match(self.ctx.bw.http_origin, self.variables["CORS_ALLOW_ORIGIN"])
	then
		self.logger:log(WARN, "origin " .. self.ctx.bw.http_origin .. " is not allowed")
		return self:ret(true, "origin " .. self.ctx.bw.http_origin .. " is not allowed")
	end
	-- Set headers
	if self.variables["CORS_ALLOW_ORIGIN"] == "*" then
		ngx_header["Access-Control-Allow-Origin"] = "*"
	else
		ngx_header["Access-Control-Allow-Origin"] = self.ctx.bw.http_origin
	end
	for variable, header in pairs(self.all_headers) do
		if self.variables[variable] ~= "" then
			ngx_header[header] = self.variables[variable]
		end
	end
	if self.ctx.bw.request_method == "OPTIONS" then
		for variable, header in pairs(self.preflight_headers) do
			if variable == "CORS_ALLOW_CREDENTIALS" then
				if self.variables["CORS_ALLOW_CREDENTIALS"] == "yes" then
					ngx_header[header] = "true"
				end
			elseif self.variables[variable] ~= "" then
				ngx_header[header] = self.variables[variable]
			end
		end
		ngx_header["Content-Type"] = "text/html; charset=UTF-8"
		ngx_header["Content-Length"] = "0"
		return self:ret(true, "edited headers for preflight request")
	end
	return self:ret(true, "edited headers for standard request")
end

function cors:access()
	-- Check if access is needed
	if self.variables["USE_CORS"] ~= "yes" then
		return self:ret(true, "service doesn't use CORS")
	end
	-- Deny as soon as possible if needed
	if
		self.ctx.bw.http_origin
		and self.variables["CORS_DENY_REQUEST"] == "yes"
		and self.variables["CORS_ALLOW_ORIGIN"] ~= "*"
		and not regex_match(self.ctx.bw.http_origin, self.variables["CORS_ALLOW_ORIGIN"])
	then
		return self:ret(
			true,
			"origin " .. self.ctx.bw.http_origin .. " is not allowed, denying access",
			get_deny_status(),
			nil,
			{
				id = "origin",
				origin = self.ctx.bw.http_origin,
			}
		)
	end
	-- Send CORS policy with a 204 (no content) status
	if self.ctx.bw.request_method == "OPTIONS" and self.ctx.bw.http_origin then
		return self:ret(true, "preflight request", HTTP_NO_CONTENT)
	end
	return self:ret(true, "standard request")
end

return cors
