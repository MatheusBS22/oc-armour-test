-- server.lua — roda no PC fixo
-- 1 Linked Card: fala com o drone (Par 2)
-- O drone consulta armaduras e repassa missões

local component  = require("component")
local event      = require("event")
local serial     = require("serialization")
local filesystem = require("filesystem")
local P          = dofile("/home/protocol.lua")

if not component.isAvailable("tunnel") then
    error("Linked Card não encontrada no PC!")
end

local tunnel    = component.tunnel
local SAVE_PATH = "/home/armors.json"

local function load()
    if not filesystem.exists(SAVE_PATH) then return {} end
    local f = io.open(SAVE_PATH, "r")
    local raw = f:read("*a")
    f:close()
    return serial.unserialize(raw) or {}
end

local function save(armors)
    local f = io.open(SAVE_PATH, "w")
    f:write(serial.serialize(armors))
    f:close()
end

local function nextId(armors)
    local max = 0
    for _, a in ipairs(armors) do
        if a.id > max then max = a.id end
    end
    return max + 1
end

local function findIndex(armors, id)
    for i, a in ipairs(armors) do
        if a.id == id then return i end
    end
    return nil
end

local armors   = load()
local handlers = {}

handlers["PING"] = function(data)
    return { ok = true, role = "server" }
end

handlers[P.MSG_LIST] = function(data)
    return { ok = true, armors = armors }
end

handlers[P.MSG_GET] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "ID " .. tostring(data.id) .. " não encontrado" }
    end
    return { ok = true, armor = armors[idx] }
end

handlers[P.MSG_ADD] = function(data)
    if not data.name or not data.x or not data.y or not data.z then
        return { ok = false, error = "Campos obrigatórios: name, x, y, z" }
    end
    local armor = {
        id   = nextId(armors),
        name = tostring(data.name),
        x    = tonumber(data.x),
        y    = tonumber(data.y),
        z    = tonumber(data.z),
    }
    table.insert(armors, armor)
    save(armors)
    return { ok = true, armor = armor }
end

handlers[P.MSG_EDIT] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "ID " .. tostring(data.id) .. " não encontrado" }
    end
    local a = armors[idx]
    if data.name then a.name = tostring(data.name) end
    if data.x    then a.x   = tonumber(data.x)     end
    if data.y    then a.y   = tonumber(data.y)      end
    if data.z    then a.z   = tonumber(data.z)      end
    save(armors)
    return { ok = true, armor = a }
end

handlers[P.MSG_REMOVE] = function(data)
    local idx = findIndex(armors, data.id)
    if not idx then
        return { ok = false, error = "ID " .. tostring(data.id) .. " não encontrado" }
    end
    local removed = armors[idx]
    table.remove(armors, idx)
    save(armors)
    return { ok = true, armor = removed }
end

print("╔══════════════════════════════╗")
print("║   SERVIDOR DE ARMADURAS OC   ║")
print("╚══════════════════════════════╝")
print("Canal: " .. tunnel.getChannel())
print("Armaduras carregadas: " .. #armors)
print("")

while true do
    local _, _, _, _, _, raw = event.pull("modem_message")
    if raw then
        local ok, msg = pcall(serial.unserialize, raw)
        if not ok or type(msg) ~= "table" or not msg.type then
            print("[!] Mensagem inválida")
        else
            local handler = handlers[msg.type]
            local response
            if not handler then
                response = { ok = false, error = "Tipo desconhecido: " .. msg.type }
            else
                local success, result = pcall(handler, msg.data or {})
                response = success and result or { ok = false, error = tostring(result) }
            end
            print("[" .. msg.type .. "] → " .. (response.ok and "OK" or "ERRO"))
            response.replyType = P.MSG_REPLY
            tunnel.send(serial.serialize(response))
        end
    end
end
