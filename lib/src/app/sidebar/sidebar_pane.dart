/// Which pane the sidebar shows — selectable from the View menu (File Tree,
/// Outline, Articles, Search), matching the reference editor's sidebar.
library;

enum SidebarPane { fileTree, outline, articles, search }

extension SidebarPaneLabel on SidebarPane {
  String get label => switch (this) {
        SidebarPane.fileTree => 'Files',
        SidebarPane.outline => 'Outline',
        SidebarPane.articles => 'Articles',
        SidebarPane.search => 'Search',
      };
}
