--- Gather configuration options.
--
-- The module reads configuration options from multiple sources
-- and then merges the options together according to source priority:
--
-- 1. `--<VARNAME>` command line arguments.
-- 2. `TARANTOOL_<VARNAME>` environment variables.
-- 3. Configuration files.
--
-- To specify a configuration file, use the `--cfg <CONFIG_FILE>` option
-- or the `TARANTOOL_CFG=<CONFIG_FILE>` environment variable.
--
-- Configuration files are `.yaml` files, divided into
-- sections like the following:
--
--     default:
--       memtx_memory: 10000000
--       some_option: "default value"
--     myapp.router:
--       memtx_memory: 1024000000
--       some_option: "router-specific value"
--
--  Within the configuration file, `argparse` looks for multiple matching sections:
--
-- 1. The section named `<APP_NAME>.<INSTANCE_NAME>` is parsed first.
--   The application name is derived automatically from the rockspec filename in the
--   project directory. Alternatively, you can specify it manually via the `--app-name`
--   command line argument or the `TARANTOOL_APP_NAME` environment variable.
--   The instance name can be specified the same way, either as `--instance-name`
--   or `TARANTOOL_INSTANCE_NAME`.
-- 2. The common `<APP_NAME>` section is parsed next.
-- 3. Finally, the section `[default]` with the global configuration is parsed
--   with the lowest priority.
--
-- An instance name may consist of multiple period-separated parts,
-- for example, `--app-name "myapp" --instance-name "router.1"`.
-- In this case, sections with names that include these parts are also parsed:
-- first `[myapp.router.1]`, then `[myapp.router]`, then `[myapp]`.
--
-- Instead of a single configuration file, you can use a directory.
-- In this case, all files in the directory are parsed.
-- To avoid conflicts, the same section mustn't repeat across different files.
--
-- @module cartridge.argparse

local fio = require('fio')
local yaml = require('yaml')
local checks = require('checks')
local errors = require('errors')
-- local base_dir = fio.abspath(fio.dirname(arg[0]))

local vars = require('cartridge.vars').new('cartridge.argparse')
local utils = require('cartridge.utils')
vars:new('args', nil)

local ParseConfigError = errors.new_class('ParseConfigError')
local DecodeYamlError = errors.new_class('DecodeYamlError')
local TypeCastError = errors.new_class('TypeCastError')

local function toboolean(val)
    if type(val) == 'boolean' then
        return val
    elseif type(val) ~= 'string' then
        return nil
    end

    val = val:lower()

    if val == 'true' then
        return true
    elseif val == 'false' then
        return false
    end
end

--- Common `cartridge.cfg` options.
--
-- Any options not listed below (like the `roles` option)
-- can't be modified with `argparse` and should be configured in code.
--
-- @table cluster_opts
local cluster_opts = {
    alias = 'string', -- **string**
    workdir = 'string', -- **string**
    http_port = 'number', -- **number**
    http_host = 'string', -- **string**
    http_enabled = 'boolean', -- **boolean**
    webui_enabled = 'boolean', -- **boolean**
    webui_prefix = 'string', -- **string**
    webui_enforce_root_redirect = 'boolean', -- **boolean**
    advertise_uri = 'string', -- **string**
    cluster_cookie = 'string', -- **string**
    console_sock = 'string', -- **string**
    auth_enabled = 'boolean', -- **boolean**
    bucket_count = 'number', -- **number**
    upgrade_schema = 'boolean', -- **boolean**
    swim_broadcast = 'boolean', -- **boolean**
    upload_prefix = 'string', -- **string**
}

--- Common `box.cfg <https://www.tarantool.io/en/doc/latest/reference/configuration/>`_ tuning options.
-- @table box_opts
local box_opts = {
    listen                   = 'string', -- **string**
    memtx_memory             = 'number', -- **number**
    strip_core               = 'boolean', -- **boolean**
    memtx_min_tuple_size     = 'number', -- **number**
    memtx_max_tuple_size     = 'number', -- **number**
    memtx_use_mvcc_engine    = 'boolean', -- **boolean**
    slab_alloc_factor        = 'number', -- **number**
    work_dir                 = 'string', -- **string** (**deprecated**)
    memtx_dir                = 'string', -- **string**
    wal_dir                  = 'string', -- **string**
    vinyl_dir                = 'string', -- **string**

    vinyl_memory             = 'number', -- **number**
    vinyl_cache              = 'number', -- **number**
    vinyl_max_tuple_size     = 'number', -- **number**
    vinyl_read_threads       = 'number', -- **number**
    vinyl_write_threads      = 'number', -- **number**
    vinyl_timeout            = 'number', -- **number**
    vinyl_run_count_per_level = 'number', -- **number**
    vinyl_run_size_ratio     = 'number', -- **number**
    vinyl_range_size         = 'number', -- **number**
    vinyl_page_size          = 'number', -- **number**
    vinyl_bloom_fpr          = 'number', -- **number**

    log                      = 'string', -- **string**
    audit_log                = 'string', -- **string**
    log_nonblock             = 'boolean', -- **boolean**
    audit_nonblock           = 'boolean', -- **boolean**
    log_level                = 'number', -- **number**
    log_format               = 'string', -- **string**
    io_collect_interval      = 'number', -- **number**
    readahead                = 'number', -- **number**
    snap_io_rate_limit       = 'number', -- **number**
    too_long_threshold       = 'number', -- **number**
    wal_mode                 = 'string', -- **string**
    rows_per_wal             = 'number', -- **number**
    wal_max_size             = 'number', -- **number**
    wal_dir_rescan_delay     = 'number', -- **number**
    force_recovery           = 'boolean', -- **boolean**
    replication              = 'string', -- **string**
    instance_uuid            = 'string', -- **string**
    replicaset_uuid          = 'string', -- **string**
    custom_proc_title        = 'string', -- **string**
    pid_file                 = 'string', -- **string**
    background               = 'boolean', -- **boolean**
    username                 = 'string', -- **string**
    coredump                 = 'boolean', -- **boolean**
    checkpoint_interval      = 'number', -- **number**
    checkpoint_wal_threshold = 'number', -- **number**
    checkpoint_count         = 'number', -- **number**
    read_only                = 'boolean', -- **boolean**
    hot_standby              = 'boolean', -- **boolean**
    worker_pool_threads      = 'number', -- **number**
    replication_timeout      = 'number', -- **number**
    replication_sync_lag     = 'number', -- **number**
    replication_sync_timeout = 'number', -- **number**
    replication_connect_timeout = 'number', -- **number**
    replication_connect_quorum = 'number', -- **number**
    replication_skip_conflict = 'boolean', -- **boolean**
    replication_synchro_quorum = 'number', -- **number**
    replication_synchro_timeout = 'number', -- **number**
    feedback_enabled         = 'boolean', -- **boolean**
    feedback_host            = 'string', -- **string**
    feedback_interval        = 'number', -- **number**
    net_msg_max              = 'number', -- **number**
}

local function load_file(filename)
    checks('string')
    local data, err = utils.file_read(filename)
    if data == nil then
        return nil, err
    end

    local file_sections, err
    if filename:endswith('.yml') or filename:endswith('.yaml') then
        local ok, ret = pcall(yaml.decode, data)
        if ok then
            file_sections = ret
        else
            err = DecodeYamlError:new('%s: %s', filename, ret)
        end
    else
        err = ParseConfigError:new('%s: Unsupported file type', filename)
    end

    if file_sections == nil then
        return nil, err
    end

    return file_sections
end

local function load_dir(dirname)
    local files = {}
    utils.table_append(files, fio.glob(fio.pathjoin(dirname, '*.yml')))
    utils.table_append(files, fio.glob(fio.pathjoin(dirname, '*.yaml')))
    table.sort(files)

    local ret = {}
    local origin = {}

    for _, f in pairs(files) do
        local file_sections, err = load_file(f)
        if file_sections == nil then
            return nil, err
        end

        for section_name, content in pairs(file_sections) do
            if ret[section_name] == nil then
                ret[section_name] = {}
                origin[section_name] = fio.basename(f)
            else
                return nil, ParseConfigError:new(
                    'collision of section %q in %s between %s and %s',
                    section_name, dirname, origin[section_name], fio.basename(f)
                )
            end

            for argname, argvalue in pairs(content) do
                ret[section_name][argname:lower()] = argvalue
            end
        end
    end

    return ret
end

local function parse_args()
    local ret = {}

    local stop = false
    local i = 0
    while i < #arg do
        i = i + 1

        if arg[i] == '--' then
            stop = true
        elseif stop then
            table.insert(ret, arg[i])
        elseif arg[i]:startswith('--') then
            local argname = arg[i]:lower():gsub('^%-%-', ''):gsub('-', '_')
            local argvalue = arg[i+1]
            i = i + 1
            ret[argname] = argvalue or ''
        else
            table.insert(ret, arg[i])
        end
    end

    return ret
end

local function parse_env()
    local ret = {}
    for argname, argvalue in pairs(os.environ()) do
        argname = string.lower(argname)

        if argname:startswith('tarantool_') then
            argname = argname:gsub("^tarantool_", ''):gsub("-", "_")
            ret[argname] = argvalue
        end
    end

    return ret
end

local function parse_file(filename, app_name, instance_name)
    checks('string', '?string', '?string')

    local file_sections, err

    if filename:endswith('/') then
        file_sections, err = load_dir(filename)
    else
        file_sections, err = load_file(filename)
    end

    if file_sections == nil then
        return nil, err
    end

    local section_names = {'default'}

    do -- generate section names to be parsed
        app_name = app_name and string.strip(app_name) or ''
        if app_name ~= '' then
            table.insert(section_names, app_name)
        end

        instance_name = instance_name and string.strip(instance_name) or ''
        if instance_name ~= '' then
            local parts = instance_name:split('.')
            for n = 1, #parts do
                local section_name = table.concat(parts, '.', 1, n)
                if app_name ~= '' then
                    section_name = app_name .. '.' .. section_name
                end
                table.insert(section_names, section_name)
            end
        end
    end

    local ret = {}
    for _, section_name in ipairs(section_names) do
        local content = file_sections[section_name]

        if section_name ~= 'default'
        and section_name ~= app_name
        and content == nil then
            -- When an instance's name can't be found in file_sections,
            -- the instance shouldn't be started. Such behavior would violate
            -- https://github.com/tarantool/cartridge/issues/1437
            return nil, ParseConfigError:new('Missing section: %s', section_name)
        end
        content = content or {}

        for argname, argvalue in pairs(content) do
            ret[argname:lower()] = argvalue
        end
    end

    return ret
end

local function supplement(to, from)
    checks('table', 'table')
    for argname, argvalue in pairs(from) do
        if to[argname] == nil then
            to[argname] = argvalue
        end
    end

    return to
end

--- Parse command line arguments, environment variables, and configuration files.
--
-- For example, running an application as follows:
--    TARANTOOL_MY_CUSTOM_ARG='value' ./init.lua --alias router --memtx-memory 100
-- results in:
--    local argparse = require('cartridge.argparse')
--    argparse.parse()
--    ---
--    - memtx_memory: '100'
--      my_custom_arg: value
--      alias: router
--    ...
--
-- @function parse
-- @treturn {argname=value,...}
local function _parse()
    local args = {}

    supplement(args, parse_args())
    supplement(args, parse_env())

    if args.app_name == nil then
        local app_dir = fio.dirname(arg[0])
        local rockspecs = fio.glob(fio.pathjoin(app_dir, '*-scm-1.rockspec'))

        if #rockspecs == 1 then
            args.app_name = string.match(fio.basename(rockspecs[1]), '^(%g+)%-scm%-1%.rockspec$')
        end
    end

    if args.cfg == nil then
        return args
    end

    if fio.path.is_dir(args.cfg) and not args.cfg:endswith('/') then
        args.cfg = args.cfg .. '/'
    end

    local cfg, err = parse_file(args.cfg, args.app_name, args.instance_name)
    if not cfg then
        return nil, err
    else
        supplement(args, cfg)
    end

    return args
end

local function parse()
    if vars.args ~= nil then
        return vars.args
    end

    local args, err = _parse()
    if args == nil then
        return nil, err
    end

    vars.args = args
    return args
end

--- Filter the results of parsing and cast variables to a given type.
--
-- From all the configuration options gathered by `parse`, select only those
-- specified in the filter.
--
-- For example, running an application as follows:
--    TARANTOOL_ARG1='value' tarantool ./init.lua --arg2 100 --arg3 true
-- results in:
--    local opts, err = argparse.get_opts({
--        arg1 = 'string',
--        arg2 = 'number',
--        arg3 = 'boolean'
--        missing_arg = 'string', -- no such arg, argparse returns nothing for this arg
--    })
--    ---
--    - arg1: value
--      arg2: 100
--      arg3: true
--    ...
--
-- @function get_opts
-- @tparam {argname=type,...} filter
-- @treturn {argname=value,...}
local function get_opts(opts)
    local args = parse()

    local ret = {}
    for optname, opttype in pairs(opts) do
        local value = args[optname]
        if value == nil then -- luacheck: ignore 542
            -- ignore
        elseif type(value) == opttype then
            ret[optname] = value
        elseif type(value) == 'number' and opttype == 'string' then
            ret[optname] = tostring(value)
        elseif type(value) == 'string' then
            local _value
            if opttype == 'number' then
                _value = tonumber(value)
            elseif opttype == 'boolean' then
                _value = toboolean(value)
            else
                return nil, TypeCastError:new(
                    "can't typecast %s to %s (unsupported type)",
                    optname, opttype
                )
            end

            if _value == nil then
                return nil, TypeCastError:new(
                    "can't typecast %s=%q to %s",
                    optname, value, opttype
                )
            end

            ret[optname] = _value
        else
            return nil, TypeCastError:new(
                "invalid configuration parameter %s (%s expected, got %s)",
                optname, opttype, type(value)
            )
        end
    end

    return ret
end

return {
    parse = parse,

    get_opts = get_opts,

    --- Shorthand for `get_opts(box_opts)`.
    -- @function get_box_opts
    get_box_opts = function()
        return get_opts(box_opts)
    end,

    --- Shorthand for `get_opts(cluster_opts)`.
    -- @function get_cluster_opts
    get_cluster_opts = function()
        return get_opts(cluster_opts)
    end,
}
