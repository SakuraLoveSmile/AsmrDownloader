import 'package:asmr_downloader/pages/components/middle_ellipsis_text.dart';
import 'package:asmr_downloader/pages/window_title_bar/move_window.dart';
import 'package:asmr_downloader/services/download/download_providers.dart';
import 'package:asmr_downloader/models/track_item.dart';
import 'package:asmr_downloader/ui/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Tracks extends ConsumerStatefulWidget {
  const Tracks({
    super.key,
    required this.rootFolder,
    this.tracksLPadding = 20.0,
  });
  final Folder rootFolder;
  final double tracksLPadding;

  @override
  ConsumerState<Tracks> createState() => TracksState();
}

class TracksState extends ConsumerState<Tracks> {
  @override
  Widget build(BuildContext context) {
    final trackExpansionLs = trackExpansion(widget.rootFolder);
    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) => trackExpansionLs[index],
            childCount: trackExpansionLs.length,
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: MoveWindow(
            //this container will fill the remaining space in the ViewPort
            child: Container(),
          ),
        ),
      ],
    );
  }

  List<Widget> trackExpansion(TrackItem track) {
    List<Widget> trackWidgets = [];
    final scheme = Theme.of(context).colorScheme;
    final roundedShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    if (track is Folder) {
      trackWidgets.add(
        Padding(
          padding: EdgeInsets.only(left: widget.tracksLPadding, bottom: 2),
          child: ExpansionTile(
            shape: roundedShape,
            collapsedShape: roundedShape,
            leading: const Icon(Icons.folder_rounded, color: AppColors.folder, size: 20),
            trailing: Checkbox(
                value: track.selected,
                onChanged: (bool? newValue) {
                  if (newValue == null) return;
                  setState(() {
                    track.setSelection(newValue);
                  });
                  ref.read(rootFolderProvider.notifier).state =
                      widget.rootFolder;
                }),
            title: Text(
              track.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            children: track.children
                .expand((child) => trackExpansion(child))
                .toList(),
          ),
        ),
      );
    } else {
      // FileAsset
      trackWidgets.add(
        Padding(
          padding: EdgeInsets.only(left: widget.tracksLPadding, bottom: 1),
          child: CheckboxListTile(
            value: track.selected,
            shape: roundedShape,
            hoverColor: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            visualDensity: VisualDensity.compact,
            onChanged: (bool? newValue) {
              if (newValue == null) return;
              setState(() {
                track.selected = newValue;
              });
              ref.read(rootFolderProvider.notifier).state = widget.rootFolder;
            },
            title: Row(
              children: [
                getIconFromType(track.type),
                const SizedBox(width: 8.0),
                ...ellipsisInMiddle(
                  track.title,
                  textStyle: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return trackWidgets;
  }

  Icon getIconFromType(String type) {
    switch (type) {
      case 'audio':
        return const Icon(Icons.music_note_rounded, color: AppColors.audio, size: 17);
      case 'image':
        return const Icon(Icons.image_outlined, color: AppColors.image, size: 17);
      case 'text':
        return const Icon(Icons.description_outlined, color: AppColors.textFile, size: 17);
      default:
        return Icon(Icons.insert_drive_file_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 17);
    }
  }
}
