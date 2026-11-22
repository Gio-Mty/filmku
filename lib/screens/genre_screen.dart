import 'package:flutter/material.dart';

import '../data/backend.dart';
import '../data/films.dart';
import '../models/film.dart';
import '../theme.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_header.dart';

class GenreScreen extends StatefulWidget {
  const GenreScreen({super.key, required this.genre});
  final String genre;

  @override
  State<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends State<GenreScreen> {
  final List<Film> _films = [];
  final ScrollController _scrollController = ScrollController();
  int _page = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400) {
      if (!_isLoading && !_isLoadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  Future<List<Film>> _fetchPage(int page) {
    final genreId = genreIdMap[widget.genre];
    if (widget.genre == 'Drakor') {
      return Backend.tmdbKDrama(page: page);
    } else if (widget.genre == 'Drakor On-Going') {
      return Backend.tmdbKDramaAiring(page: page);
    } else if (widget.genre == 'Drakor Romantis') {
      return Backend.tmdbKDramaRomance(page: page);
    } else if (widget.genre == 'Drakor Thriller') {
      return Backend.tmdbKDramaThriller(page: page);
    } else if (genreId != null) {
      return Backend.tmdbDiscover(genre: genreId, page: page);
    } else {
      return Backend.tmdbSearch(widget.genre, page: page);
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        _films.clear();
        _films.addAll(list);
        _page = 1;
        _hasMore = list.length >= 20;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _page + 1;
      final list = await _fetchPage(nextPage);
      if (!mounted) return;
      setState(() {
        _films.addAll(list);
        _page = nextPage;
        _hasMore = list.length >= 20;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.genre),
        backgroundColor: AppColors.bg,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null && _films.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gagal memuat: $_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadInitial,
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (_films.isEmpty) {
      return const EmptyState(
        icon: Icons.movie_outlined,
        message: 'Tidak ada film ditemukan untuk genre ini.',
      );
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _loadInitial,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.54,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => PosterCard(film: _films[index]),
                childCount: _films.length,
              ),
            ),
          ),
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              ),
            ),
          if (!_hasMore && _films.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Semua film telah dimuat',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
