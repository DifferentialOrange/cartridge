local gql_types = require('graphql.types')
local lua_api_boxinfo = require('cartridge.lua-api.boxinfo')

local gql_type_error = gql_types.object({
    name = 'Error',
    fields = {
        message = gql_types.string.nonNull,
        class_name = gql_types.string,
        stack = gql_types.string,
    }
})

local gql_replica_status = gql_types.object({
    name = 'ReplicaStatus',
    description = 'Statistics for an instance in the replica set.',
    fields = {
        id = gql_types.int,
        lsn = gql_types.long,
        uuid = gql_types.string.nonNull,
        upstream_status = gql_types.string,
        upstream_message = gql_types.string,
        upstream_idle = gql_types.float,
        upstream_peer = gql_types.string,
        upstream_lag = gql_types.float,
        downstream_status = gql_types.string,
        downstream_message = gql_types.string,
    },
})

local gql_vshard_router = gql_types.object({
    name = 'VshardRouter',
    fields = {
        vshard_group = {
            kind = gql_types.string,
            description = 'Vshard group',
        },
        buckets_available_ro = {
            kind = gql_types.int,
            description = 'The number of buckets known to the router' ..
                ' and available for read requests',
        },
        buckets_available_rw = {
            kind = gql_types.int,
            description = 'The number of buckets known to the router' ..
                ' and available for read and write requests',
        },
        buckets_unreachable = {
            kind = gql_types.int,
            description = 'The number of buckets known to the router' ..
                ' but unavailable for any requests',
        },
        buckets_unknown = {
            kind = gql_types.int,
            description = 'The number of buckets whose replica' ..
                ' sets are not known to the router',
        },
    }
})

local boxinfo_schema = {
    kind = gql_types.object({
        name = 'ServerInfo',
        description = 'Server information and configuration.',
        fields = {
            general = gql_types.object({
                name = 'ServerInfoGeneral',
                fields = {
                    version = {
                        kind = gql_types.string.nonNull,
                        description = 'The Tarantool version',
                    },
                    pid = {
                        kind = gql_types.int.nonNull,
                        description = 'The process ID',
                    },
                    uptime = {
                        kind = gql_types.float.nonNull,
                        description = 'The number of seconds since the instance started',
                    },
                    instance_uuid = {
                        kind = gql_types.string.nonNull,
                        description = 'A globally unique identifier of the instance',
                    },
                    replicaset_uuid = {
                        kind = gql_types.string.nonNull,
                        description = 'The UUID of the replica set',
                    },

                    work_dir = {
                        kind = gql_types.string,
                        description = 'Current working directory of a process',
                    },
                    memtx_dir = {
                        kind = gql_types.string,
                        description = 'A directory where memtx stores snapshot (.snap) files',
                    },
                    vinyl_dir = {
                        kind = gql_types.string,
                        description = 'A directory where vinyl files or subdirectories will be stored',
                    },
                    wal_dir = {
                        kind = gql_types.string,
                        description = 'A directory where write-ahead log (.xlog) files are stored',
                    },
                    worker_pool_threads = {
                        kind = gql_types.int,
                        description =
                            'The maximum number of threads to use' ..
                            ' during execution of certain internal processes' ..
                            ' (currently socket.getaddrinfo() and coio_call())',
                    },


                    listen = {
                        kind = gql_types.string,
                        description = 'The binary protocol URI',
                    },
                    http_port = {
                        kind = gql_types.int,
                        description = 'HTTP port',
                    },
                    http_host = {
                        kind = gql_types.string,
                        description = 'HTTP host',
                    },
                    webui_prefix = {
                        kind = gql_types.string,
                        description = 'HTTP webui prefix',
                    },
                    ro = {
                        kind = gql_types.boolean.nonNull,
                        description = 'Current read-only state',
                    },
                }
            }).nonNull,
            storage = gql_types.object({
                name = 'ServerInfoStorage',
                fields = {
                    -- wal
                    too_long_threshold = {
                        kind = gql_types.float,
                        description = '',
                    },
                    wal_dir_rescan_delay = {
                        kind = gql_types.float,
                        description = '',
                    },
                    wal_max_size = {
                        kind = gql_types.long,
                        description = '',
                    },
                    wal_mode = {
                        kind = gql_types.string,
                        description = '',
                    },
                    rows_per_wal = {
                        kind = gql_types.long,
                        description = '',
                    },

                    -- memtx
                    memtx_memory = {
                        kind = gql_types.long,
                        description = '',
                    },
                    memtx_max_tuple_size = {
                        kind = gql_types.long,
                        description = '',
                    },
                    memtx_min_tuple_size = {
                        kind = gql_types.long,
                        description = '',
                    },

                    -- vinyl
                    vinyl_bloom_fpr = gql_types.float,
                    vinyl_cache = gql_types.long,
                    vinyl_memory = gql_types.long,
                    vinyl_max_tuple_size = gql_types.long,
                    vinyl_page_size = gql_types.long,
                    vinyl_range_size = gql_types.long,
                    vinyl_run_size_ratio = gql_types.float,
                    vinyl_run_count_per_level = gql_types.int,
                    vinyl_timeout = gql_types.float,
                    vinyl_read_threads = gql_types.int,
                    vinyl_write_threads = gql_types.int,
                },
            }).nonNull,
            network = gql_types.object({
                name = 'ServerInfoNetwork',
                fields = {
                    net_msg_max = {
                        kind = gql_types.long,
                        description = '',
                    },
                    readahead = {
                        kind = gql_types.long,
                        description = '',
                    },
                    io_collect_interval = {
                        kind = gql_types.float,
                        description = '',
                    },
                },
            }).nonNull,
            replication = gql_types.object({
                name = 'ServerInfoReplication',
                fields = {
                    replication_connect_quorum = {
                        kind = gql_types.int,
                        description = '',
                    },
                    replication_connect_timeout = {
                        kind = gql_types.float,
                        description = '',
                    },
                    replication_skip_conflict = {
                        kind = gql_types.boolean,
                        description = '',
                    },
                    replication_sync_lag = {
                        kind = gql_types.float,
                        description = '',
                    },
                    replication_sync_timeout = {
                        kind = gql_types.float,
                        description = '',
                    },
                    replication_timeout = {
                        kind = gql_types.float,
                        description = '',
                    },
                    vclock = {
                        kind = gql_types.list(gql_types.long),
                        description =
                            'The vector clock of' ..
                            ' replication log sequence numbers',
                    },
                    replication_info = {
                        kind = gql_types.list(gql_replica_status),
                        description =
                            'Statistics for all instances' ..
                            ' in the replica set in regard to the' ..
                            ' current instance',
                    },
                }
            }).nonNull,
            cartridge = gql_types.object({
                name = 'ServerInfoCartridge',
                fields = {
                    version = {
                        kind = gql_types.string.nonNull,
                        description = 'Cartridge version',
                    },
                    state = {
                        kind = gql_types.string.nonNull,
                        description = 'Current instance state',
                    },
                    error = {
                        kind = gql_type_error,
                        description =
                            'Error details if instance is in' ..
                            ' failure state',
                    }
                }
            }).nonNull,
            membership = gql_types.object({
                name = 'ServerInfoMembership',
                fields = {
                    status = {
                        kind = gql_types.string,
                        description = 'Status of the instance',
                    },
                    incarnation = {
                        kind = gql_types.int,
                        description = 'Value incremented every time the instance ' ..
                            'became a suspect, dead, or updates its payload',
                    },
                    PROTOCOL_PERIOD_SECONDS = {
                        kind = gql_types.float,
                        description = 'Direct ping period',
                    },
                    ACK_TIMEOUT_SECONDS = {
                        kind = gql_types.float,
                        description = 'ACK message wait time',
                    },
                    ANTI_ENTROPY_PERIOD_SECONDS = {
                        kind = gql_types.float,
                        description = 'Anti-entropy synchronization period',
                    },
                    SUSPECT_TIMEOUT_SECONDS = {
                        kind = gql_types.float,
                        description = 'Timeout to mark a suspect dead',
                    },
                    NUM_FAILURE_DETECTION_SUBGROUPS = {
                        kind = gql_types.int,
                        description = 'Number of members to ping a suspect indirectly',
                    },
                }
            }).nonNull,
            vshard_router = {
                kind = gql_types.list(gql_vshard_router),
                description = 'List of vshard router parameters',
            },
            vshard_storage = gql_types.object({
                name = 'ServerInfoVshardStorage',
                fields = {
                    vshard_group = {
                        kind = gql_types.string,
                        description = 'Vshard group',
                    },
                    buckets_receiving = {
                        kind = gql_types.int,
                        description = 'The number of buckets that are receiving at this time',
                    },
                    buckets_active = {
                        kind = gql_types.int,
                        description = 'The number of active buckets on the storage',
                    },
                    buckets_total = {
                        kind = gql_types.int,
                        description = 'Total number of buckets on the storage',
                    },
                    buckets_garbage = {
                        kind = gql_types.int,
                        description = 'The number of buckets that are waiting to be collected by GC',
                    },
                    buckets_pinned = {
                        kind = gql_types.int,
                        description = 'The number of pinned buckets on the storage',
                    },
                    buckets_sending = {
                        kind = gql_types.int,
                        description = 'The number of buckets that are sending at this time',
                    },
                }
            }),
        }
    }),
    arguments = {},
    resolve = function(root, _)
        return lua_api_boxinfo.get_info(root.uri), nil
    end,
}

return {
    schema = boxinfo_schema,
}
