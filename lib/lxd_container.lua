--- cofu custom resources for LXD client

define "lxd_container" {
    -- Container name. required.
    name = "",

    -- Image name (e.g. "images:ubuntu/xenial/amd64")
    image = "",

    -- State is one of started, stopped, frozen, restarted or absent.
    state = "started",

    -- Whether or not force stop
    force_stop = false,

    -- Whether or not force delete.
    force_delete = false,

    -- Whether or not wait for all devices have IPv4 addresses.
    wait_for_ipv4_addresses = true,

    (function()
        local Container = {}

        function Container:new(attrs)
            attrs = attrs or {}
            setmetatable(attrs, self)
            self.__index = self
            return attrs
        end

        function Container:launch(image)
            local cmd = string.format("lxc launch %q %q", image, self.name)
            return run_command(cmd)
        end

        function Container:start()
            local cmd = string.format("lxc start %q", self.name)
            return run_command(cmd)
        end

        function Container:restart(force_stop)
            local opt = ""
            if force_stop then
                opt = " --force"
            end
            local cmd = string.format("lxc restart%s %q", opt, self.name)
            return run_command(cmd)
        end

        function Container:stop(force_stop)
            local opt = ""
            if force_stop then
                opt = " --force"
            end
            local cmd = string.format("lxc stop%s %q", opt, self.name)
            return run_command(cmd)
        end

        function Container:pause()
            local cmd = string.format("lxc pause %q", self.name)
            return run_command(cmd)
        end

        function Container:delete(force_delete)
            local opt = ""
            if force_delete then
                opt = " --force"
            end
            local cmd = string.format("lxc delete%s %q", opt, self.name)
            return run_command(cmd)
        end

        function Container:get_info()
            local cmd = string.format("LANG=C lxc info %q", self.name)
            return run_command(cmd)
        end

        local function each_line(text)
            return string.gmatch(text, "([^\n]*)\n?")
        end

        local function split_words(text)
            local words = {}
            for word in string.gmatch(text, "[^%s]+") do
                words[#words + 1] = word
            end
            return words
        end

        local lxcInfoToCofuStateMap = {
            Running = "started",
            Stopped = "stopped",
            Frozen = "frozen"
        }

        function Container:get_state()
            local res = self:get_info()
            for line in each_line(res:stdout()) do
                local words = split_words(line)
                local name = words[1]
                if name == "Status:" then
                    return lxcInfoToCofuStateMap[words[2]]
                end
            end
            return "absent"
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
                        local words = split_words(line)
                        local name = string.gsub(words[1], ":", "")
                        if name ~= "lo" then
                            local ver = words[2]
                            local addr = words[3]
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

        function Container:wait_for_all_devices_to_have_v4addr()
            while true do
                local res = self:get_info()
                if all_devices_have_v4addr(res:stdout()) then
                    break
                end
                run_command("sleep 1")
            end
        end

        return function (attrs)
            local c = Container:new{name=attrs.name}
            local oldState = c:get_state()
            if attrs.state == "started" then
                if oldState == "absent" then
                    c:launch(attrs.image)
                elseif oldState == "frozen" then
                    c:start()
                elseif oldState == "stopped" then
                    c:start()
                end
                if attrs.wait_for_ipv4_addresses then
                    c:wait_for_all_devices_to_have_v4addr()
                end
            elseif attrs.state == "frozen" then
                if oldState == "absent" then
                    c:launch(attrs.image)
                    c:pause()
                elseif oldState == "started" then
                    c:pause()
                elseif oldState == "stopped" then
                    c:start()
                    c:pause()
                end
            elseif attrs.state == "stopped" then
                if oldState == "absent" then
                    c:launch(attrs.image)
                    c:stop(attrs.force_stop)
                elseif oldState == "started" then
                    c:stop(attrs.force_stop)
                elseif oldState == "frozen" then
                    c:start()
                    c:stop(attrs.force_stop)
                end
            elseif attrs.state == "restarted" then
                if oldState == "absent" then
                    c:launch(attrs.image)
                elseif oldState == "started" then
                    c:restart(attrs.force_stop)
                elseif oldState == "frozen" then
                    c:start()
                    c:restart(attrs.force_stop)
                end
            elseif attrs.state == "absent" then
                if oldState ~= "absent" then
                    if attrs.force_delete then
                        c:delete(true)
                    else
                        if oldState == "started" then
                            c:stop(attrs.force_stop)
                            c:delete(false)
                        elseif oldState == "frozen" then
                            c:start()
                            c:stop(attrs.force_stop)
                            c:delete(false)
                        elseif oldState == "stopped" then
                            c:delete(false)
                        end
                    end
                end
            end
        end
    end)()
}
