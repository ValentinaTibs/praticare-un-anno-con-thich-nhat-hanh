import 'package:flutter/material.dart';
import '../core/models/user.dart';

/// A page of the admin panel, listed in the side navigation.
class PanelSection {
  final String path;
  final String label;
  final IconData icon;

  /// What the page will do, shown until the page is built.
  final String description;
  final bool superAdminOnly;

  const PanelSection({
    required this.path,
    required this.label,
    required this.icon,
    required this.description,
    this.superAdminOnly = false,
  });
}

const panelSections = [
  PanelSection(
    path: '/utenti',
    label: 'Utenti e gruppi',
    icon: Icons.groups_outlined,
    description: 'Gruppi e loro membri; revisione, sospensione, ban e rimozione degli utenti.',
  ),
  PanelSection(
    path: '/in-attesa',
    label: 'In attesa',
    icon: Icons.hourglass_empty,
    description: 'Utenti in attesa e richiedenti del prossimo percorso, con la motivazione.',
  ),
  PanelSection(
    path: '/canale-principale',
    label: 'Canale Principale',
    icon: Icons.campaign_outlined,
    description: 'Sequenza dei post programmati per giorno dall\'inizio del gruppo, con le bozze.',
  ),
  PanelSection(
    path: '/conferme',
    label: 'Conferme',
    icon: Icons.fact_check_outlined,
    description: 'Round di conferma di appartenenza per gruppo e il loro andamento.',
  ),
  PanelSection(
    path: '/cerchio',
    label: 'Cerchio',
    icon: Icons.forum_outlined,
    description: 'Programmazione settimanale del cerchio e moderazione dei messaggi.',
  ),
  PanelSection(
    path: '/frasi',
    label: 'Frasi del giorno',
    icon: Icons.format_quote_outlined,
    description: 'Frasi dell\'anno e frasi del percorso, con import da CSV.',
  ),
  PanelSection(
    path: '/cicli',
    label: 'Cicli',
    icon: Icons.event_outlined,
    description: 'Apertura dei cicli con data di chiusura, data di inizio e durata del percorso.',
    superAdminOnly: true,
  ),
  PanelSection(
    path: '/ruoli',
    label: 'Ruoli',
    icon: Icons.admin_panel_settings_outlined,
    description: 'Promozione e declassamento degli admin.',
    superAdminOnly: true,
  ),
  PanelSection(
    path: '/testi',
    label: 'Testi',
    icon: Icons.edit_note,
    description: 'Testi dei messaggi per sospesi, bannati e ciclo chiuso, ed email di contatto.',
    superAdminOnly: true,
  ),
];

/// Sections the user may open: the super admin ones only for the super admin.
List<PanelSection> sectionsFor(User user) =>
    panelSections.where((s) => !s.superAdminOnly || user.isSuperAdmin).toList();
