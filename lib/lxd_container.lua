--- cofu custom resources for LXD client

local lxc = (function()
    local lxcInfoToCofuStateMap = {
        [""] = "absent",
        Running = "started",
        Stopped = "stopped",
        Frozen = "frozen"
    }

    local function get_state(name)
        local cmd = string.format([[LANG=C lxc info %q | awk '$1=="Status:"{printf("%%s", $2)}']], name)
        local res = run_command(cmd)
        return lxcInfoToCofuStateMap[res:stdout()]
    end

    local function launch(name, image)
        local cmd = string.format("lxc launch %q %q", image, name)
        return run_command(cmd)
    end

    local function start(name, image)
        local cmd = string.format("lxc start %q", name)
        return run_command(cmd)
    end

    local function stop(name, force)
        local opt = ""
        if force then
            opt = " --force"
        end
        local cmd = string.format("lxc stop%s %q", opt, name)
        return run_command(cmd)
    end

    local function delete(name, force)
        local opt = ""
        if force then
            opt = " --force"
        end
        local cmd = string.format("lxc delete%s %q", opt, name)
        return run_command(cmd)
    end

    local function info(name)
        local cmd = string.format("LANG=C lxc info %q", name)
        return run_command(cmd)
    end

    local function each_line(text)
        return string.gmatch(text, "([^\n]*)\n?")
    end

    local function each_word(text)
        return string.gmatch(text, "[^%s]+")
    end

    local function ipv4_addresses(info_stdout)
        local ipv4Addresses = {}
        local ipv6Addresses = {}
        local seen_ips_header = false
        for line in each_line(info_stdout) do
            if seen_ips_header then
                if line == "Resources:" then
                    break
                else
                    print("line=" .. line .. "!")
                    local m = string.match(line, "%s+(%w+):%s+(%w+)%s+(%w+)%s*(%w*)")
                    print("#m=" .. #m)
                end
            else
                if line == "Ips:" then
                    seen_ips_header = true
                end
            end
        end
    end

    local function all_devices_have_v4addr(info_stdout)
        local v4AddrCount = 0
        local v6AddrCount = 0
        local seen_ips_header = false
        for line in each_line(info_stdout) do
            if seen_ips_header then
                if line == "Resources:" then
                    seen_ips_header = false
                else
                    local iter, s = each_word(line)
                    local name = string.gsub(iter(s), ":", "")
                    if name ~= "lo" then
                        local ver = iter(s)
                        local addr = iter(s)
                        if ver == "inet" then
                            v4AddrCount = v4AddrCount + 1
                        elseif ver == "inet6" then
                            v6AddrCount = v6AddrCount + 1
                        end
                    end
                end
            else
                if line == "Ips:" then
                    seen_ips_header = true
                end
            end
        end
        return v4AddrCount == v6AddrCount
    end

    local function wait_for_all_devices_have_v4addr(name)
        while true do
            local res = info(name)
            if all_devices_have_v4addr(res:stdout()) then
                break
            end
            run_command("sleep 1")
        end
    end

    return {
        info = info,
        ipv4_addresses = ipv4_addresses,
        get_state = get_state,
        launch = launch,
        start = start,
        stop = stop,
        delete = delete,
        wait_for_all_devices_have_v4addr =  wait_for_all_devices_have_v4addr
    }
end)()

define "lxd_container" {
    -- Container name. required.
    name = "",

    -- Image name (e.g. "images:ubuntu/xenial/amd64")
    image = "",

    -- State is one of started, stopped, frozen, absent.
    state = "started",

    -- Whether or not force stop
    force_stop = false,

    -- Whether or not force delete.
    force_delete = false,

    -- Whether or not wait for all devices have IPv4 addresses.
    wait_for_all_devices_have_v4addr = true,

    function (attrs)
        local oldState = lxc.get_state(attrs.name)
        if attrs.state == "started" then
            if oldState == "absent" then
                lxc.launch(attrs.name, attrs.image)
                if attrs.wait_for_all_devices_have_v4addr then
                    lxc.wait_for_all_devices_have_v4addr(attrs.name)
                end
            elseif oldState == "stopped" then
                lxc.start(attrs.name)
            end
        elseif attrs.state == "stopped" then
            if oldState == "started" then
                lxc.stop(attrs.name, attrs.force_stop)
            end
        elseif attrs.state == "absent" then
            if oldState ~= "absent" then
                lxc.delete(attrs.name, attrs.force_delete)
            end
        end
    end
}
