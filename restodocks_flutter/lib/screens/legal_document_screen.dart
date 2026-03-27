import 'package:flutter/material.dart';
import '../legal/legal_texts.dart';

enum LegalDocumentType { privacyPolicy, publicOffer }

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.type});

  final LegalDocumentType type;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = type == LegalDocumentType.privacyPolicy;
    return Scaffold(
      appBar: AppBar(
        title:
            Text(isPrivacy ? 'Политика конфиденциальности' : 'Договор оферты'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                isPrivacy ? privacyPolicyFullTextRu : publicOfferFullTextRu,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
