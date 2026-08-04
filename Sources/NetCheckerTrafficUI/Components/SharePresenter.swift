import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Показ системного меню «Поделиться».
///
/// Раньше вызывающие места брали `connectedScenes.first` и `windows.first`.
/// Ни то, ни другое не гарантирует активную сцену и ключевое окно: при нескольких
/// сценах, на iPad со Split View или когда первая сцена ушла в фон, презентация
/// уходила в невидимый контроллер и внешне выглядела как «кнопка ничего не делает».
enum SharePresenter {

    /// Показать системный share sheet с указанными объектами
    static func present(items: [Any]) {
        #if os(iOS)
        guard !items.isEmpty, let host = topViewController() else { return }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // На iPad share sheet показывается поповером и без якоря падает
        if let popover = controller.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(
                x: host.view.bounds.midX,
                y: host.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        host.present(controller, animated: true)
        #endif
    }

    #if os(iOS)
    /// Самый верхний контроллер активной сцены
    static func topViewController() -> UIViewController? {
        guard let window = keyWindow() else { return nil }

        var controller = window.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    /// Ключевое окно активной на переднем плане сцены
    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        // Сначала ищем сцену на переднем плане, и только потом откатываемся
        // к любой доступной — порядок connectedScenes не определён
        let ordered = scenes.filter { $0.activationState == .foregroundActive } + scenes

        for scene in ordered {
            if let key = scene.windows.first(where: \.isKeyWindow) {
                return key
            }
        }
        return ordered.first?.windows.first
    }
    #endif
}
