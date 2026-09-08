local _, NS = ...

local PixelPerfect = {}

NS.PixelPerfect = PixelPerfect

local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local DEFAULT_BACKGROUND_COLOR = { r = 0.015, g = 0.018, b = 0.022, a = 0.95 }
local DEFAULT_BORDER_COLOR = { r = 0.38, g = 0.41, b = 0.45, a = 0.9 }
local DEFAULT_BORDER_PIXELS = 1

local borders = setmetatable({}, { __mode = "k" })
local refreshPending = false

local function setTextureColor(texture, color)
    texture:SetVertexColor(color.r, color.g, color.b, color.a or 1)
end

function PixelPerfect.DisablePixelSnap(texture)
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

function PixelPerfect.CreateBackground(frame, color, drawLayer, subLevel)
    local texture = frame:CreateTexture(
        nil,
        drawLayer or "BACKGROUND",
        nil,
        subLevel
    )

    texture:SetAllPoints(frame)
    texture:SetTexture(WHITE_TEXTURE)
    PixelPerfect.DisablePixelSnap(texture)
    setTextureColor(texture, color or DEFAULT_BACKGROUND_COLOR)

    return texture
end

local function createBorderTexture(container, drawLayer, subLevel, color)
    local texture = container:CreateTexture(nil, drawLayer, nil, subLevel)

    texture:SetTexture(WHITE_TEXTURE)
    PixelPerfect.DisablePixelSnap(texture)
    setTextureColor(texture, color)

    return texture
end

local function refreshBorder(frame, border)
    if border.size <= 0 then
        border.container:Hide()
        return
    end

    local container = border.container
    local pixelSize = PixelUtil.GetPixelToUIUnitFactor()
        / container:GetEffectiveScale()
    local edgeSize = math.max(1, math.floor(border.size + 0.5))
        * pixelSize

    container:SetFrameLevel(frame:GetFrameLevel() + 1)
    container:Show()

    border.top:ClearAllPoints()
    border.top:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    border.top:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    border.top:SetHeight(edgeSize)

    border.bottom:ClearAllPoints()
    border.bottom:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    border.bottom:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    border.bottom:SetHeight(edgeSize)

    border.left:ClearAllPoints()
    border.left:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -edgeSize)
    border.left:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, edgeSize)
    border.left:SetWidth(edgeSize)

    border.right:ClearAllPoints()
    border.right:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -edgeSize)
    border.right:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, edgeSize)
    border.right:SetWidth(edgeSize)
end

function PixelPerfect.SetBorderColor(frame, color)
    local border = borders[frame]

    assert(border, "frame does not have a pixel-perfect border")
    border.color = color
    setTextureColor(border.top, color)
    setTextureColor(border.bottom, color)
    setTextureColor(border.left, color)
    setTextureColor(border.right, color)
end

function PixelPerfect.CreateBorder(frame, size, color, drawLayer, subLevel)
    local border = borders[frame]

    if border then
        border.size = size or border.size
        PixelPerfect.SetBorderColor(frame, color or border.color)
        refreshBorder(frame, border)
        return border.container
    end

    color = color or DEFAULT_BORDER_COLOR
    drawLayer = drawLayer or "OVERLAY"
    subLevel = subLevel or 7

    local container = CreateFrame("Frame", nil, frame)

    container:SetAllPoints(frame)
    container:EnableMouse(false)

    border = {
        container = container,
        size = size or DEFAULT_BORDER_PIXELS,
        color = color,
        top = createBorderTexture(container, drawLayer, subLevel, color),
        bottom = createBorderTexture(container, drawLayer, subLevel, color),
        left = createBorderTexture(container, drawLayer, subLevel, color),
        right = createBorderTexture(container, drawLayer, subLevel, color),
    }
    borders[frame] = border

    refreshBorder(frame, border)
    frame:HookScript("OnShow", PixelPerfect.RequestRefresh)
    PixelPerfect.RequestRefresh()

    return container
end

function PixelPerfect.CreateSurface(
    frame,
    backgroundColor,
    borderColor,
    borderSize
)
    local background = PixelPerfect.CreateBackground(frame, backgroundColor)

    PixelPerfect.CreateBorder(
        frame,
        borderSize or DEFAULT_BORDER_PIXELS,
        borderColor
    )

    return background
end

function PixelPerfect.RefreshAll()
    for frame, border in pairs(borders) do
        refreshBorder(frame, border)
    end
end

function PixelPerfect.RequestRefresh()
    if refreshPending then
        return
    end

    refreshPending = true
    C_Timer.After(0, function()
        refreshPending = false
        PixelPerfect.RefreshAll()
    end)
end

local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", PixelPerfect.RequestRefresh)
