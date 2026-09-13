import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_interaction_gate.dart';

void main() {
  group('ReaderInteractionGate.resolve 原因优先级', () {
    test('全部空闲时放行', () {
      expect(
        ReaderInteractionGate.resolve(
          isPaginating: false,
          boundaryRequestInFlight: false,
          pageAnimationActive: false,
          pageTransitionInFlight: false,
        ),
        ReaderInteractionBlockReason.none,
      );
    });

    test('加载/切章优先级最高', () {
      expect(
        ReaderInteractionGate.resolve(
          isPaginating: true,
          boundaryRequestInFlight: true,
          pageAnimationActive: true,
          pageTransitionInFlight: true,
        ),
        ReaderInteractionBlockReason.chapterSwitching,
      );
    });

    test('边界请求优先于动画与过渡', () {
      expect(
        ReaderInteractionGate.resolve(
          isPaginating: false,
          boundaryRequestInFlight: true,
          pageAnimationActive: true,
          pageTransitionInFlight: true,
        ),
        ReaderInteractionBlockReason.boundaryTransition,
      );
    });

    test('动画优先于过渡', () {
      expect(
        ReaderInteractionGate.resolve(
          isPaginating: false,
          boundaryRequestInFlight: false,
          pageAnimationActive: true,
          pageTransitionInFlight: true,
        ),
        ReaderInteractionBlockReason.pageAnimation,
      );
    });

    test('仅过渡在途时表达为过渡收尾窗口', () {
      expect(
        ReaderInteractionGate.resolve(
          isPaginating: false,
          boundaryRequestInFlight: false,
          pageAnimationActive: false,
          pageTransitionInFlight: true,
        ),
        ReaderInteractionBlockReason.pageTransition,
      );
    });
  });

  group('ReaderInteractionGate 判定语义', () {
    test('拖拽与外部命令：任何非 none 原因都阻塞', () {
      for (final reason in ReaderInteractionBlockReason.values) {
        expect(
          ReaderInteractionGate.blocksInput(reason),
          reason != ReaderInteractionBlockReason.none,
          reason: reason.name,
        );
      }
    });

    test('点击热区翻页：放行过渡收尾窗口，其余全部阻塞', () {
      expect(
        ReaderInteractionGate.blocksTapTurn(
          ReaderInteractionBlockReason.pageTransition,
        ),
        isFalse,
        reason: 'PointerUp 与 ScrollStart 竞态窗口不得吞掉点击翻页',
      );
      for (final reason in ReaderInteractionBlockReason.values) {
        if (reason == ReaderInteractionBlockReason.pageTransition) {
          continue;
        }
        expect(
          ReaderInteractionGate.blocksTapTurn(reason),
          reason != ReaderInteractionBlockReason.none,
          reason: reason.name,
        );
      }
    });

    test('PageView physics：仅切章与边界期锁死滚动', () {
      expect(
        ReaderInteractionGate.locksScroll(
          ReaderInteractionBlockReason.chapterSwitching,
        ),
        isTrue,
      );
      expect(
        ReaderInteractionGate.locksScroll(
          ReaderInteractionBlockReason.boundaryTransition,
        ),
        isTrue,
      );
      expect(
        ReaderInteractionGate.locksScroll(
          ReaderInteractionBlockReason.pageAnimation,
        ),
        isFalse,
      );
      expect(
        ReaderInteractionGate.locksScroll(
          ReaderInteractionBlockReason.pageTransition,
        ),
        isFalse,
      );
      expect(
        ReaderInteractionGate.locksScroll(ReaderInteractionBlockReason.none),
        isFalse,
      );
    });
  });
}
