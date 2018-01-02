---
--- Created by zhangpei-home.
--- DateTime: 2017/10/3 21:07
---

local skynet = require("skynet")
local room_conf = require("room_conf")
local logger = require("logger")

-- room_id -> {members -> [uid -> {agent, userdata}], info -> {room_id, room_name}}
local room_list = {}

-- uid -> room_id
local uid2roomid = {}

-- use for dispatch
local CMD = {}

function CMD.enter_room(room_id, userdata, agent)
    local member = {
        agent = agent,
        userdata = userdata
    }

    local room = room_list[room_id]
    if room then
        -- send notify to each member in room
        for _, v in pairs(room.members) do
            skynet.call(v.agent, "lua", "notify_user_enter_room", room_id, userdata)
        end

        room.members[userdata.uid] = member
        room_list[room_id] = room
        uid2roomid[userdata.uid] = room_id

        return {
            result = true
        }
    else
        logger.warn("room_implement", "invalid room_id", room_id)
        return {
            result = false
        }
    end
end

function CMD.leave_room(uid)
    local room_id = uid2roomid[uid]
    if not room_id then
        logger.info("room_implement", "leave_room", "uid not exist", uid)
        return {
            result = false
        }
    end

    local room = room_list[room_id]
    assert(room, "room not exist in room_list")

    local userdata = room.members[uid].userdata

    -- send notify to each member in room
    for k, v in pairs(room.members) do
        if k ~= uid then
            skynet.call(v.agent, "lua", "notify_user_leave_room", room_id, userdata)
        end
    end

    -- clear user
    room.members[uid] = nil
    room_list[room_id] = room
    uid2roomid[uid] = nil

    return {
        result = true
    }
end

function CMD.list_rooms()
    local room_infos = {}
    for _, room in pairs(room_list) do
        room_infos [#room_infos + 1] = room.info
    end
    return {
        room_infos = room_infos
    }
end

function CMD.list_members(uid)
    local room_id = uid2roomid[uid]
    if not room_id then
        return {
            result = false,
            members = nil
        }
    end

    local room = room_list[room_id]
    if room then
        local members = {}
        for uid, v in pairs(room.members) do
            local member = {
                uid = v.userdata.uid,
                name = v.userdata.name,
                exp = v.userdata.exp
            }
            members[#members + 1] = member
        end
        return {
            result = true,
            members = members
        }
    else
        logger.error("room_implement", "invalid room_id", room_id)
        return {
            result = false,
            members = nil
        }
    end
end

function CMD.say_public(uid, content)
    local room_id = uid2roomid[uid]
    if not room_id then
        logger.warn("room_implement", "say_public", "uid not exist", uid)
        return {
            result = false
        }
    end

    local room = room_list[room_id]
    assert(room, "room not exist in room_list")

    local userdata = room.members[uid].userdata

    -- send notify to each member in room
    for k, v in pairs(room.members) do
        if k ~= uid then
            skynet.call(v.agent, "lua", "notify_user_talking_message", userdata, v.userdata, "public", content)
        end
    end

    return {
        result = true
    }
end

function CMD.say_private(from_uid, to_uid, content)
    local room_id = uid2roomid[from_uid]
    if not room_id then
        logger.warn("room_implement", "say_private", "from_uid not exist", from_uid)
        return {
            result = false
        }
    end

    local room = room_list[room_id]
    assert(room, "room not exist in room_list")

    local from_userdata = room.members[from_uid].userdata
    local to_member = room.members[to_uid]
    if not to_member then
        logger.warn("room_implement", "say_private", "to_uid not exist in room", to_uid, room_id)
        return {
            result = false
        }
    end

    skynet.call(to_member.agent, "lua", "notify_user_talking_message", from_userdata, to_member.userdata, "private", content)

    return {
        result = true
    }
end

local function room_init()
    for _, v in pairs(room_conf) do
        local room = {
            members = {},
            info = {
                id = v.id,
                name = v.name
            }
        }
        room_list[v.id] = room
        logger.info("room_implement", "create_room", v.id, v.name)
    end
end

skynet.start(function()
    room_init()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(...)))
    end)
end)
