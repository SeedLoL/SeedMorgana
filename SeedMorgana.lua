module("SeedMorgana", package.seeall, log.setup)
clean.module("SeedMorgana", package.seeall, log.setup)

-- Globals
local CoreEx = _G.CoreEx
local Libs = _G.Libs

local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local SpellLib = Libs.Spell
local TargetSelector = Libs.TargetSelector

local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Renderer = CoreEx.Renderer

local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChance = Enums.HitChance
local HitChanceStrings = {"Collision", "OutOfRange", "VeryLow", "Low", "Medium", "High", "VeryHigh", "Dashing",
                          "Immobile"};

local Player = ObjectManager.Player.AsHero

if Player.CharName ~= "Morgana" then
    return false
end

-- Spells
local Q = SpellLib.Skillshot({
    Slot = SpellSlots.Q,
    Range = 1200,
    Radius = 70,
    Speed = 1200,
    Delay = 0.00,
    Collisions = {
        Heroes = true,
        Minions = true,
        WindWall = true,
        Wall = false
    },
    UseHitbox = true,
    Type = "Linear"
})
local W = SpellLib.Skillshot({
    Slot = SpellSlots.W,
    Speed = 999,
    Range = 900,
    Delay = 0.25,
    Radius = 175,
    Type = "Circular"
})
local E = SpellLib.Active({
    Slot = SpellSlots.E,
    Range = 800
})
local R = SpellLib.Active({
    Slot = SpellSlots.R,
    Range = 615,
    Delay = 0.25
})

local Utils = {}
local Morgana = {}

Morgana.Menu = nil
Morgana.TargetSelector = nil
Morgana.Logic = {}

function Utils.StringContains(str, sub)
    return string.find(str, sub, 1, true) ~= nil
end

function Utils.GameAvailable()
    return not (Game.IsChatOpen() or Game.IsMinimized() or Player.IsDead or Player.IsRecalling)
end

function Utils.WithinMinRange(Target, Min)
    local Distance = Player:EdgeDistance(Target.Position)
    if Distance >= Min then
        return true
    end
    return false
end

function Utils.WithinMaxRange(Target, Max)
    local Distance = Player:EdgeDistance(Target.Position)
    if Distance <= Max then
        return true
    end
    return false
end

function Utils.InRange(Range, Type)
    return #(Morgana.TargetSelector:GetValidTargets(Range, ObjectManager.Get("enemy", Type), false))
end

function Utils.GetRedBlueJungle(Range)
    local Minions = ObjectManager.Get("neutral", "minions")
    for _, Minion in pairs(Minions) do
        Minion = Minion.AsMinion
        if Minion and Minion.IsTargetable and
            (Minion.Name == "SRU_Red4.1.1" or Minion.Name == "SRU_Red10.1.1" or Minion.Name == "SRU_Blue1.1.1" or
                Minion.Name == "SRU_Blue7.1.1") then
            if Utils.WithinMaxRange(Minion, Range) then
                return Minion
            end
        end
    end
    return false
end

function Morgana.Logic.Q(MustUse, HitChance)
    if not MustUse then
        return false
    end
    local QTarget = Q:GetTarget()
    if (QTarget and Q:IsReady() and Utils.WithinMinRange(QTarget, Orbwalker.GetTrueAutoAttackRange(QTarget))) then
        if Q:CastOnHitChance(QTarget, HitChance) then
            return true
        end
    end
    return false
end

function Morgana.Logic.W(MustUse)
    if not MustUse then
        return false
    end
    local rPositions = {}
    if W:IsReady() and not Q:IsReady() then
        for _, v in pairs(ObjectManager.Get("enemy", "heroes")) do
            local target = v.AsHero
            if target.IsAlive and target.Position:Distance(Player.Position) <= W.Range then
                local rPos = target:FastPrediction(W.Delay)
                table.insert(rPositions, rPos)
            end
        end
        if #rPositions > 0 then
            local bestWPos, wHitCount = Geometry.BestCoveringCircle(rPositions, W.Radius)
            if wHitCount >= Menu.Get("Combo.W.MinHit") then
                if Input.Cast(SpellSlots.W, bestWPos) then
                    return true
                end
            end
        end
    end
end

function Morgana.Logic.E(MustUse)
    if not MustUse then
        return false
    end
    local ETarget = Orbwalker.GetTarget() -- E:GetTarget()
    if (ETarget and E:IsReady()) then
        if E:Cast() then
            return true
        end
    end
end

function Morgana.Logic.R(MustUse, InRangeCount)
    if not MustUse then
        return false
    end
    local RTarget = R:GetTarget()
    if (RTarget and R:IsReady() and Utils.InRange(R.Range, "heroes") >= InRangeCount) then
        if R:Cast() then
            return true
        end
    end
end

function Morgana.Logic.CalcQDmg(Target)
    local Level = Q:GetLevel()
    local BaseDamage = ({80, 135, 190, 245, 300})[Level]
    local RawDamage = BaseDamage + (0.9 * Player.TotalAP)
    return DamageLib.CalculateMagicalDamage(Player, Target, RawDamage)
end
function Morgana.Logic.CalcRDmg(Target)
    local Level = R:GetLevel()
    local BaseDamage = ({150, 225, 300})[Level]
    local RawDamage = BaseDamage + (Player.TotalAP * 0.7)
    return DamageLib.CalculateMagicalDamage(Player, Target, RawDamage)
end

function Morgana.Logic.QSteal(MustUse)
    if not MustUse then
        return false
    end
    local Minion = Utils.GetRedBlueJungle(Q.Range)
    if Minion and Morgana.Logic.CalcQDmg(Minion) >= Minion.Health then
        if Q:IsReady() and Q:Cast(Minion) then
            return true
        end
    end
    return false
end
function Morgana.Logic.DragonBaronSnipe(MustUse)
    if not MustUse then
        return
    end
    for k, v in pairs(ObjectManager.Get("neutral", "minions")) do
        if (Utils.StringContains(v.Name, "SRU_Dragon") or Utils.StringContains(v.Name, "SRU_Baron") or
            Utils.StringContains(v.Name, "SRU_Rift")) then
            if v.IsAlive and v.Position:Distance(Player.Position) < Q.Range then
                if v.Health < Morgana.Logic.CalcQDmg(v) then
                    if Q:IsReady() and Q:Cast(v) then
                        return true
                    end
                end
            end
        end
    end
end
function Morgana.Logic.Killsteal()
    if Menu.Get("Killsteal.Q.Use") or Menu.Get("Killsteal.R.Use") then
        for _, v in pairs(ObjectManager.Get("ally", "heroes")) do
            local ally = v.AsHero
            if not ally.IsMe and not ally.IsDead then
                for _, b in pairs(ObjectManager.Get("enemy", "heroes")) do
                    local enemy = b.AsHero
                    if not enemy.IsDead and enemy.IsTargetable then
                        if Menu.Get("Killsteal.Q.Use") and Q:IsReady() and Q:IsInRange(enemy) then
                            if enemy.Health <= Morgana.Logic.CalcQDmg(enemy) then
                                local qpos = enemy:FastPrediction(Q.Delay)
                                if qpos then
                                    Q:CastOnHitChance(enemy, Menu.Get("Killsteal.Q.HitChance"))
                                end
                            end
                        end
                        if Menu.Get("Killsteal.R.Use") and R:IsReady() and R:IsInRange(enemy) then
                            if enemy.Health <= Morgana.Logic.CalcRDmg(enemy) then
                                R:Cast()
                            end
                        end
                    end
                end
            end
        end

    end
end
function Morgana.OnProcessSpell(Caster, SpellCast)
    if Player.IsRecalling then
        return
    end
    if Caster.IsEnemy then
        if SpellCast.Target ~= nil then
            if not SpellCast.IsBasicAttack then
                if SpellCast.Target and (SpellCast.Target == Player or SpellCast.Target.IsAlly) then
                    if Player.Position:Distance(SpellCast.Target.Position) < E.Range then
                        return Input.Cast(SpellSlots.E, Player.Position)
                    end
                end
            end
        end
    end
end
function Morgana.OnDrawDamage(target, dmgList)
    local dmg = 0
    if Q:IsReady() then
        dmg = dmg + Morgana.Logic.CalcQDmg(target)
    end
    if R:IsReady() then
        dmg = dmg + Morgana.Logic.CalcRDmg(target)
    end
    table.insert(dmgList, dmg)
end
function Morgana.OnHeroImmobilized(Source, EndTime, IsStasis)
    if Player.IsRecalling then
        return
    end
    if Source.IsEnemy and Source.IsHero and not Source.IsDead and Source.IsTargetable then
        if Menu.Get("Immo.Q.Use") and Q:IsReady() and EndTime - Game.GetTime() < Menu.Get("Immo.Q.TimeRemaining") then
            if Player.Position:Distance(Source.Position) <= Q.Range then
                if Source.Position then
                    return Q:CastOnHitChance(Source, HitChance.VeryHigh)
                end
            end
        end
        if Menu.Get("Immo.W.Use") and W:IsReady() and EndTime - Game.GetTime() > 1.5 then
            if Player.Position:Distance(Source.Position) <= W.Range then
                if Source.Position then
                    return Input.Cast(SpellSlots.W, Source.Position)
                end
            end
        end
    end
end

function Morgana.Logic.Combo()
    if (Morgana.Logic.Q(Menu.Get("Combo.Q.Use"), Menu.Get("Combo.Q.HitChance"))) then
        return true
    end
    if (Morgana.Logic.W(Menu.Get("Combo.W.Use"))) then
        return true
    end
    if (Morgana.Logic.R(Menu.Get("Combo.R.Use"), Menu.Get("Combo.R.MinHit"))) then
        return true
    end
    return false
end

function Morgana.Logic.Harass()
    if (Morgana.Logic.Q(Menu.Get("Harass.Q.Use"), Menu.Get("Harass.Q.HitChance"))) then
        return true
    end
end

function Utils.ValidMinion(minion)
    return minion and minion.IsTargetable and not minion.IsDead and minion.MaxHealth > 6
end

function Morgana.Logic.Lasthit()
    if Player.Mana / Player.MaxMana * 100 >= Menu.Get("LastHit.MinMana") then
        if Menu.Get("LastHit.Q.Mode") ~= 0 and Q:IsReady() then
            for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                local minion = v.AsMinion
                if minion.IsAlive and
                    (Menu.Get("LastHit.Q.Mode") == 2 and minion.IsSiegeMinion or Menu.Get("LastHit.Q.Mode") == 1) then
                    local qpos = minion:FastPrediction(Q.Delay)
                    if qpos:Distance(Player.Position) < Q.Range and minion.Health <= Morgana.Logic.CalcQDmg(minion) then
                        return Q:CastOnHitChance(minion, Menu.Get("LastHit.Q.HitChance"))
                    end
                end
            end
        end
    end
end

function Morgana.Logic.Flee()
    if Menu.Get("Flee.E.Use") and E:IsReady() then
        Input.Cast(SpellSlots.E, Player)
    end
end

function Morgana.Logic.Waveclear()
    local wPositions = {}
    if Player.Mana / Player.MaxMana * 100 >= Menu.Get("LaneClear.MinMana") then
        if Menu.Get("LaneClear.Q.Use") and Q:IsReady() then
            for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                local minion = v.AsMinion
                if minion.IsSiegeMinion and minion.IsAlive then
                    local qpos = minion:FastPrediction(Q.Delay)
                    if qpos:Distance(Player.Position) < Q.Range then
                        if minion.Health <= Morgana.Logic.CalcQDmg(minion) then
                            return Q:CastOnHitChance(minion, Menu.Get("LaneClear.Q.HitChance"))
                        end
                    end
                end
            end
        end
        if Menu.Get("LaneClear.W.Use") and W:IsReady() then
            for _, v in pairs(ObjectManager.Get("enemy", "minions")) do
                local minion = v.AsMinion
                if Utils.ValidMinion(minion) then
                    local wPos = minion:FastPrediction(W.Delay)
                    if wPos:Distance(Player.Position) < W.Range then
                        table.insert(wPositions, wPos)
                    end
                end
            end
            if #wPositions > 0 then
                local bestWPos, wHitCount = Geometry.BestCoveringCircle(wPositions, W.Radius)
                if bestWPos and wHitCount >= Menu.Get("LaneClear.W.MinHit") then
                    return Input.Cast(SpellSlots.W, bestWPos)
                end
            end
        end
    end
end

function Morgana.LoadMenu()
    Menu.RegisterMenu("SeedMorgana", "Seed's Morgana", function()
        Menu.NewTree("Morgana.comboMenu", "Combo Settings", function()
            Menu.ColumnLayout("Casting", "Casting", 2, true, function()
                Menu.ColoredText("Combo", 0xB65A94FF, true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Combo.Q.Use", "Use", true)
                Menu.Dropdown("Combo.Q.HitChance", "HitChance", 5, HitChanceStrings)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("Combo.W.Use", "Use", true)
                Menu.Slider("Combo.W.MinHit", "Min Hit", 3, 1, 5, 1)
                Menu.ColoredText("> R", 0x0066CCFF, false)
                Menu.Checkbox("Combo.R.Use", "Use", true)
                Menu.Slider("Combo.R.MinHit", "Min Hit", 2, 1, 5, 1)
                Menu.NextColumn()
                Menu.ColoredText("Harass", 0xB65A94FF, true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Harass.Q.Use", "Use", true)
                Menu.Dropdown("Harass.Q.HitChance", "HitChance", 5, HitChanceStrings)
            end)
        end)
        Menu.NewTree("Morgana.farmMenu", "Farm Settings", function()
            Menu.ColumnLayout("Farm", "Farm", 2, true, function()
                Menu.ColoredText("LaneClear", 0xB65A94FF, true)
                Menu.Slider("LaneClear.MinMana", "Min Mana", 1, 0, 100, 5)
                Menu.ColoredText("> Q on Canon", 0x0066CCFF, false)
                Menu.Checkbox("LaneClear.Q.Use", "Use", true)
                Menu.Dropdown("LaneClear.Q.HitChance", "HitChance", 5, HitChanceStrings)
                Menu.ColoredText("> W", 0x0066CCFF, false)
                Menu.Checkbox("LaneClear.W.Use", "Use", true)
                Menu.Slider("LaneClear.W.MinHit", "Min Hit", 2, 1, 5, 1)
                Menu.NextColumn()
                Menu.ColoredText("Last Hit", 0xB65A94FF, true)
                Menu.Slider("LastHit.MinMana", "Min Mana", 1, 0, 100, 5)
                Menu.Dropdown("LastHit.Q.Mode", "Q Mode", 0, {"Off", "Any", "Canon Only"})
                Menu.Dropdown("LastHit.Q.HitChance", "HitChance", 5, HitChanceStrings)
            end)
        end)
        Menu.NewTree("Morgana.ksMenu", "Killsteal Settings", function()
            Menu.ColumnLayout("Killsteal", "Killsteal", 2, true, function()
                Menu.ColoredText("Killsteal", 0xB65A94FF, true)
                Menu.ColoredText("> Q", 0x0066CCFF, false)
                Menu.Checkbox("Killsteal.Q.Use", "Use", true)
                Menu.Dropdown("Killsteal.Q.HitChance", "HitChance", 5, HitChanceStrings)

                Menu.ColoredText("> R", 0x0066CCFF, false)
                Menu.Checkbox("Killsteal.R.Use", "Use", false)
            end)
        end)
        Menu.NewTree("Morgana.miscSettings", "Dash/Immobilize Settings", function()
            Menu.ColumnLayout("Events", "Events", 2, true, function()
                Menu.ColoredText("PlaceHolder", 0xB65A94FF, true)
                --[[Menu.ColoredText("On Dash", 0xB65A94FF, true)
                Menu.ColoredText("> Q ", 0x0066CCFF, false)
                Menu.Checkbox("Dash.Q.Use", "Use", true) ]]
                Menu.NextColumn()
                Menu.ColoredText("On Immobilize", 0xB65A94FF, true)
                Menu.ColoredText("> Chain Stun ", 0x0066CCFF, false)
                Menu.Checkbox("Immo.Q.Use", "Use", true)
                Menu.Slider("Immo.Q.TimeRemaining", "Remaining time", 0.5, 0.1, 0.5, 0.05)
                Menu.ColoredText("> W on stuns ", 0x0066CCFF, false)
                Menu.Checkbox("Immo.W.Use", "Use", true)
            end)
        end)
        Menu.Separator()
        Menu.ColumnLayout("JungleSteal", "Jungle Steal", 1, true, function()
            Menu.ColoredText("Jungle Steal", 0xB65A94FF, true)
            Menu.Keybind("JungleSteal.HotKey", "HotKey", string.byte('T'))
        end)
        Menu.Separator()
        Menu.ColumnLayout("Drawings", "Drawings", 2, true, function()
            Menu.ColoredText("Shield", 0xB65A94FF, true)
            Menu.ColoredText("> E on Flee ", 0x0066CCFF, false)
            Menu.Checkbox("Flee.E.Use", "Use", true)
            Menu.NextColumn()
            Menu.ColoredText("Drawings", 0xB65A94FF, true)
            Menu.Checkbox("Drawings.Q", "Q", true)
            Menu.ColorPicker("Drawings.Q.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.W", "W", true)
            Menu.ColorPicker("Drawings.W.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.E", "E", true)
            Menu.ColorPicker("Drawings.E.Color", "", 0xEF476FFF)
            Menu.Checkbox("Drawings.R", "R", true)
            Menu.ColorPicker("Drawings.R.Color", "", 0xEF476FFF)
        end)
    end)
end

function Morgana.OnDraw()
    if not Player.IsOnScreen or Player.IsDead then
        return false
    end
    if Menu.Get("Drawings.Q") then
        Renderer.DrawCircle3D(Player.Position, Q.Range, 30, 1, Menu.Get("Drawings.Q.Color"), 100)
    end
    if Menu.Get("Drawings.W") then
        Renderer.DrawCircle3D(Player.Position, W.Range, 30, 1, Menu.Get("Drawings.W.Color"), 100)
    end
    if Menu.Get("Drawings.E") then
        Renderer.DrawCircle3D(Player.Position, E.Range, 30, 1, Menu.Get("Drawings.E.Color"), 100)
    end
    if Menu.Get("Drawings.R") then
        Renderer.DrawCircle3D(Player.Position, R.Range, 30, 1, Menu.Get("Drawings.R.Color"), 100)
    end
    return true
end

function Morgana.OnTick()
    if not Utils.GameAvailable() then
        return false
    end
    local OrbwalkerMode = Orbwalker.GetMode()
    local OrbwalkerLogic = Morgana.Logic[OrbwalkerMode]
    if OrbwalkerLogic then
        return OrbwalkerLogic()
    end
    -- Auto stuff
    Morgana.Logic.Killsteal()
    Morgana.Logic.QSteal(Menu.Get("JungleSteal.HotKey"))
    Morgana.Logic.DragonBaronSnipe(Menu.Get("JungleSteal.HotKey"))
    return true
end

function OnLoad()
    Morgana.LoadMenu()
    Morgana.TargetSelector = TargetSelector()
    for EventName, EventId in pairs(Events) do
        if Morgana[EventName] then
            EventManager.RegisterCallback(EventId, Morgana[EventName])
        end
    end

    return true
end
