import AppKit

// Media controls for a page playing in another tab.
@MainActor
final class NowPlayingWidget: SidebarWidget {
    weak var sidebar: SidebarView?
    private(set) var tab: BrowserTab?
    private let pipButton = IconButton(symbol: "pip", size: 12, toolTip: "Picture in Picture")
    private let closeButton = IconButton(symbol: "xmark", size: 11, toolTip: "Close")
    private let iconButton = IconButton(symbol: "globe", size: 13, toolTip: "Go to Tab")
    private let previousButton = IconButton(symbol: "backward.end.fill", size: 12, toolTip: "Previous")
    private let playButton = IconButton(symbol: "pause.fill", size: 14)
    private let nextButton = IconButton(symbol: "forward.end.fill", size: 12, toolTip: "Next")
    private let muteButton = IconButton(symbol: "speaker.fill", size: 12)

    override init(frame: NSRect) {
        super.init(frame: frame)
        canExpand = true
        setAccessories([pipButton, closeButton])
        for view in [iconButton, previousButton, playButton, nextButton, muteButton] as [NSView] {
            addSubview(view)
        }
        iconButton.action = { [weak self] in self?.goToTab() }
        previousButton.action = { [weak self] in self?.tab?.tab?.previousTrack() }
        nextButton.action = { [weak self] in self?.tab?.tab?.nextTrack() }
        playButton.action = { [weak self] in
            guard let page = self?.tab?.tab else { return }
            if page.isPlayingMedia { page.pauseMedia() } else { page.playMedia() }
        }
        muteButton.action = { [weak self] in
            guard let page = self?.tab?.tab else { return }
            page.isMuted.toggle()
        }
        pipButton.action = { [weak self] in self?.tab?.tab?.togglePictureInPicture() }
        closeButton.action = { [weak self] in self?.sidebar?.controller?.dismissNowPlaying() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ tab: BrowserTab?) {
        self.tab = tab
        if let tab, let page = tab.tab {
            titleLabel.stringValue = page.mediaTitle.isEmpty ? tab.title : page.mediaTitle
            iconButton.setImage(Self.favicon(tab.favicon))
            playButton.setSymbol(page.isPlayingMedia ? "pause.fill" : "play.fill", size: 14)
            playButton.toolTip = page.isPlayingMedia ? "Pause" : "Play"
            previousButton.isEnabled = page.canPlayPreviousTrack
            nextButton.isEnabled = page.canPlayNextTrack
            muteButton.setSymbol(page.isMuted ? "speaker.slash.fill" : "speaker.fill", size: 12)
            muteButton.toolTip = page.isMuted ? "Unmute" : "Mute"
            pipButton.isEnabled = page.canEnterPictureInPicture || page.isInPictureInPicture
        }
        isPresented = tab != nil
    }

    private static func favicon(_ image: NSImage?) -> NSImage {
        guard let image else { return .symbol("globe", size: 13) ?? NSImage() }
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    private func goToTab() {
        guard let tab else { return }
        sidebar?.select(tab)
    }

    override func titleClicked() { goToTab() }

    override func layoutRow(in rect: NSRect) {
        let size: CGFloat = 26
        let controls = [iconButton, previousButton, playButton, nextButton, muteButton]
        for (index, button) in controls.enumerated() {
            let center = rect.width * (CGFloat(index) + 0.5) / CGFloat(controls.count)
            button.frame = NSRect(x: (center - size / 2).rounded(), y: rect.minY + (rect.height - size) / 2, width: size, height: size)
        }
    }
}
