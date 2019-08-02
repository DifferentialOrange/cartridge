#!/usr/bin/env tarantool

local log = require('log')
local json = require('json').new()
local yaml = require('yaml').new()
local errors = require('errors')
local http_utils = require('cluster.http-utils')

json.cfg({
    encode_use_tostring = true,
})
yaml.cfg({
    encode_use_tostring = true,
})


local auth = require('cluster.auth')
local confapplier = require('cluster.confapplier')

local TOKEN_CONFIG_KEY = require('cluster.tokens').TOKEN_CONFIG_KEY

local system_sections = {
    topology = true,
    vshard = true,
    vshard_groups = true,
    [TOKEN_CONFIG_KEY] = true,
}

local function http_finalize_error(http_code, err)
    log.error(tostring(err))
    return {
        status = http_code,
        headers = {
            ['content-type'] = "application/json",
        },
        body = json.encode(err),
    }
end

local e_download_config = errors.new_class('Config download failed')
local function download_config_handler(req)
    if not auth.check_request(req) then
        local err = e_download_config:new('Unauthorized')
        return http_utils.http_finalize_error(401, err)
    end

    local conf = confapplier.get_deepcopy()
    if conf == nil then
        local err = e_download_config:new('Cluster isn\'t bootsrapped yet')
        return http_utils.http_finalize_error(409, err)
    end

    -- cut system sections
    for k, _ in pairs(system_sections) do
        conf[k] = nil
    end

    return {
        status = 200,
        headers = {
            ['content-type'] = "application/yaml",
            ['content-disposition'] = 'attachment; filename="config.yml"',
        },
        body = yaml.encode(conf)
    }
end

local e_upload_config = errors.new_class('Config upload failed')
local e_decode_yaml = errors.new_class('Decoding YAML failed')
local function upload_config_handler(req)
    if not auth.check_request(req) then
        local err = e_upload_config:new('Unauthorized')
        return http_utils.http_finalize_error(401, err)
    end

    if confapplier.get_readonly() == nil then
        local err = e_upload_config:new('Cluster isn\'t bootsrapped yet')
        return http_utils.http_finalize_error(409, err)
    end

    local req_body = http_utils.read_request_body(req)

    local conf_new, err = nil
    if req_body == nil then
        err = e_upload_config:new('Request body must not be empty')
    else
        conf_new, err = e_decode_yaml:pcall(yaml.decode, req_body)
    end

    if err ~= nil then
        return http_utils.http_finalize_error(400, err)
    elseif type(conf_new) ~= 'table' then
        err = e_upload_config:new('Config must be a table')
        return http_finalize_error(400, err)
    end

    log.warn('Config uploaded')

    local patch = {}
    local conf_old = confapplier.get_readonly()
    for k, _ in pairs(conf_old) do
        if system_sections[k] then
            patch[k] = conf_old[k]
        else
            patch[k] = box.NULL
        end
    end
    for k, v in pairs(conf_new) do
        if system_sections[k] then
            local err = e_upload_config:new(
                "uploading system section %q is forbidden", k
            )
            return http_finalize_error(400, err)
        else
            patch[k] = v
        end
    end

    local ok, err = confapplier.patch_clusterwide(patch)
    if ok == nil then
        return http_utils.http_finalize_error(400, err)
    end

    return { status = 200 }
end

local function init(httpd)

    httpd:route({
        path = '/admin/config',
        method = 'PUT'
    }, upload_config_handler)
    httpd:route({
        path = '/admin/config',
        method = 'GET'
    }, download_config_handler)

    return true
end

return {
    init = init,
}
