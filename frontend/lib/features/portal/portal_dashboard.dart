/// Portal 仪表板对外暴露的稳定集成契约：组合根只经此引用分区状态与焦点模型，
/// 不直接依赖 `application/`、`domain/` 内部实现。
library;

export 'package:omninest/features/portal/application/portal_paged_cards.dart'
    show
        portalContinueWatchingProvider,
        portalPlaybackQueueProvider,
        portalReaderShelfProvider,
        portalRecentPhotosProvider,
        portalVideoPreviewProvider;
export 'package:omninest/features/portal/domain/portal_focus_models.dart'
    show PortalFocusModule;
