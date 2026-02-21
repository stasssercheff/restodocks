  Widget _buildTableWithFixedColumn(LocalizationService loc) {
    final leftW = _leftWidth(context);
    final screenW = MediaQuery.of(context).size.width;
    final rightW = _colTotalWidth + _colGap + _maxQuantityColumns * (_colQtyWidth + _colGap) + 48;

    return Column(
      children: [
        // Fixed header row
        Row(
          children: [
            // Fixed left header
            Container(
              width: leftW,
              child: _buildFixedHeaderRow(loc),
            ),
            // Scrollable right header
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _hScroll,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  width: rightW.clamp(screenW - leftW, double.infinity),
                  child: _buildScrollableHeaderRow(loc),
                ),
              ),
            ),
          ],
        ),
        // Scrollable content
        Expanded(
          child: Row(
            children: [
              // Fixed left column (product info)
              Container(
                width: leftW,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_blockFilter != _InventoryBlockFilter.pfOnly && _productIndices.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_block_products'), isFixed: true),
                        ..._productIndices.asMap().entries.map((e) => _buildFixedDataRow(loc, e.value, e.key + 1)),
                      ],
                      if (_blockFilter != _InventoryBlockFilter.productsOnly && _pfIndices.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_block_pf'), isFixed: true),
                        ..._pfIndices.asMap().entries.map((e) {
                          final rowNum = _blockFilter == _InventoryBlockFilter.pfOnly ? e.key + 1 : _productIndices.length + e.key + 1;
                          return _buildFixedDataRow(loc, e.value, rowNum);
                        }),
                      ],
                      if (_aggregatedFromFile != null && _aggregatedFromFile!.isNotEmpty) ...[
                        _buildSectionHeader(loc, loc.t('inventory_pf_products_title'), isFixed: true),
                        _buildFixedAggregatedHeaderRow(loc),
                        ..._aggregatedFromFile!.asMap().entries.map((e) => _buildFixedAggregatedDataRow(loc, e.value, e.key + 1)),
                      ],
                    ],
                  ),
                ),
              ),
              // Scrollable right column (quantities)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hScroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    width: rightW.clamp(screenW - leftW, double.infinity),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Empty space to align with fixed headers
                      SizedBox(height: _completed ? 56 : 48),
                      if (_blockFilter != _InventoryBlockFilter.pfOnly && _productIndices.isNotEmpty) ...[
                        SizedBox(height: 32), // Section header space
                        ..._productIndices.asMap().entries.map((e) => _buildScrollableDataRow(loc, e.value)),
                      ],
                      if (_blockFilter != _InventoryBlockFilter.productsOnly && _pfIndices.isNotEmpty) ...[
                        SizedBox(height: 32), // Section header space
                        ..._pfIndices.asMap().entries.map((e) => _buildScrollableDataRow(loc, e.value)),
                      ],
                      if (_aggregatedFromFile != null && _aggregatedFromFile!.isNotEmpty) ...[
                        SizedBox(height: 32), // Section header space
                        _buildScrollableAggregatedHeaderRow(loc),
                        ..._aggregatedFromFile!.asMap().entries.map((e) => _buildScrollableAggregatedDataRow(loc, e.value)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
