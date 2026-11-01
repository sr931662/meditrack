import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/mt_widgets.dart';

class TabIndex extends Notifier<int> {
  @override
  int build() => 0;
  void set(int i) => state = i;
}

/// Which bottom-nav tab is showing. Screens can switch tabs (e.g. "View All" on Home).
final shellTabProvider = NotifierProvider<TabIndex, int>(TabIndex.new);

class NavItem {
  const NavItem(this.label, this.icon, this.iconActive);
  final String label;
  final IconData icon;
  final IconData iconActive;
}

/// Floating pill navigation from the design: 58 px targets, blue active state.
class FloatingNav extends StatelessWidget {
  const FloatingNav({super.key, required this.items, required this.index, required this.onTap});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .96), borderRadius: BorderRadius.circular(26), border: Border.all(color: Mt.border), boxShadow: Mt.shadow(.14, 32, 12)),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    label: items[i].label,
                    child: GestureDetector(
                      onTap: () => onTap(i),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        constraints: const BoxConstraints(minHeight: 58),
                        decoration: BoxDecoration(color: i == index ? const Color(0xFFEEF5FF) : Colors.transparent, borderRadius: BorderRadius.circular(20)),
                        child: ExcludeSemantics(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(i == index ? items[i].iconActive : items[i].icon, size: 24, color: i == index ? Mt.blue : const Color(0xFF7186A3)),
                            const SizedBox(height: 3),
                            Text(items[i].label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: i == index ? FontWeight.w700 : FontWeight.w500, color: i == index ? Mt.blue : const Color(0xFF7186A3))),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
}

/// Shared shell: gradient page + IndexedStack of tabs + floating nav.
class TabShell extends ConsumerWidget {
  const TabShell({super.key, required this.items, required this.pages});
  final List<NavItem> items;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = ref.watch(shellTabProvider).clamp(0, pages.length - 1);
    return Scaffold(
      backgroundColor: Mt.page,
      extendBody: true,
      body: PageBackground(child: IndexedStack(index: i, children: pages)),
      bottomNavigationBar: FloatingNav(items: items, index: i, onTap: (v) => ref.read(shellTabProvider.notifier).set(v)),
    );
  }
}
