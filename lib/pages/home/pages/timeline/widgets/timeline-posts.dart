import 'dart:async';

import 'package:Openbook/models/circle.dart';
import 'package:Openbook/models/follows_list.dart';
import 'package:Openbook/models/post.dart';
import 'package:Openbook/models/user.dart';
import 'package:Openbook/provider.dart';
import 'package:Openbook/services/httpie.dart';
import 'package:Openbook/services/toast.dart';
import 'package:Openbook/services/user.dart';
import 'package:Openbook/widgets/buttons/button.dart';
import 'package:Openbook/widgets/icon.dart';
import 'package:Openbook/widgets/post/post.dart';
import 'package:Openbook/widgets/progress_indicator.dart';
import 'package:Openbook/widgets/theming/text.dart';
import 'package:dcache/dcache.dart';
import 'package:flutter/material.dart';
import 'package:loadmore/loadmore.dart';

class OBTimelinePosts extends StatefulWidget {
  final OBTimelinePostsController controller;

  OBTimelinePosts({
    this.controller,
  });

  @override
  OBTimelinePostsState createState() {
    return OBTimelinePostsState();
  }
}

class OBTimelinePostsState extends State<OBTimelinePosts> {
  List<Post> _posts;
  List<Circle> _filteredCircles;
  List<FollowsList> _filteredFollowsLists;
  bool _needsBootstrap;
  UserService _userService;
  ToastService _toastService;
  StreamSubscription _loggedInUserChangeSubscription;
  ScrollController _postsScrollController;

  SimpleCache<int, Widget> _postsWidgetsCache;

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  // Whether we have loaded all posts infinite-scroll wise
  bool _loadingFinished;

  // Whether there's a request in progress
  bool _refreshInProgress;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) widget.controller.attach(this);
    _postsWidgetsCache = SimpleCache(storage: SimpleStorage(size: 300));
    _posts = [];
    _filteredCircles = [];
    _filteredFollowsLists = [];
    _needsBootstrap = true;
    _loadingFinished = false;
    _refreshInProgress = false;
    _postsScrollController = ScrollController();
  }

  @override
  void dispose() {
    super.dispose();
    _loggedInUserChangeSubscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (_needsBootstrap) {
      var provider = OpenbookProvider.of(context);
      _userService = provider.userService;
      _toastService = provider.toastService;
      _bootstrap();
      _needsBootstrap = false;
    }
    return _posts.isEmpty ? _buildNoTimelinePosts() : _buildTimelinePosts();
  }

  Widget _buildTimelinePosts() {
    return RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _onRefresh,
        child: LoadMore(
            whenEmptyLoad: false,
            isFinish: _loadingFinished,
            delegate: const OBHomePostsLoadMoreDelegate(),
            child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: 200,
                addAutomaticKeepAlives: true,
                controller: _postsScrollController,
                padding: const EdgeInsets.all(0),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  var post = _posts[index];
                  return _getWidgetForPost(post);
                }),
            onLoadMore: _loadMorePosts));
  }

  Widget _buildNoTimelinePosts() {
    return SizedBox(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 200),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset(
                'assets/images/stickers/owl-instructor.png',
                height: 100,
              ),
              SizedBox(
                height: 20.0,
              ),
              OBText(
                'Your timeline is empty.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18.0,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: 10.0,
              ),
              OBText(
                'Follow users or join a community to get started!',
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: 30,
              ),
              OBButton(
                icon: OBIcon(
                  OBIcons.refresh,
                  size: OBIconSize.small,
                ),
                type: OBButtonType.highlight,
                child: Text('Refresh posts'),
                onPressed: _onRefresh,
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshingPosts() {
    return SizedBox(
      child: Center(
        child: OBProgressIndicator(),
      ),
    );
  }

  void scrollToTop() {
    _postsScrollController.animateTo(
      0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 300),
    );
  }

  void addPostToTop(Post post) {
    setState(() {
      this._posts.insert(0, post);
    });
  }

  Future<void> setFilters(
      {List<Circle> circles, List<FollowsList> followsLists}) async {
    _filteredCircles = circles;
    _filteredFollowsLists = followsLists;
    return _refreshPosts();
  }

  Future<void> clearFilters() {
    _filteredCircles = [];
    _filteredFollowsLists = [];
    return _refreshPosts();
  }

  List<Circle> getFilteredCircles() {
    return _filteredCircles.toList();
  }

  List<FollowsList> getFilteredFollowsLists() {
    return _filteredFollowsLists.toList();
  }

  void _bootstrap() async {
    _loggedInUserChangeSubscription =
        _userService.loggedInUserChange.listen(_onLoggedInUserChange);
  }

  Future<void> _onRefresh() {
    return _refreshPosts();
  }

  void _onLoggedInUserChange(User newUser) async {
    if (newUser == null) return;
    _refreshPosts();
    _loggedInUserChangeSubscription.cancel();
  }

  Future<void> _refreshPosts() async {
    _setRefreshInProgress(true);
    try {
      Post.clearCache();
      User.clearNavigationCache();
      _postsWidgetsCache.clear();

      _posts = (await _userService.getTimelinePosts(
              circles: _filteredCircles, followsLists: _filteredFollowsLists))
          .posts;
      _setPosts(_posts);
      _setLoadingFinished(false);
    } on HttpieConnectionRefusedError catch (error) {
      _onConnectionRefusedError(error);
    } catch (error) {
      _onUnknownError(error);
      rethrow;
    } finally {
      _setRefreshInProgress(false);
    }
  }

  Future<bool> _loadMorePosts() async {
    var lastPost = _posts.last;
    var lastPostId = lastPost.id;
    try {
      var morePosts = (await _userService.getTimelinePosts(
              maxId: lastPostId,
              circles: _filteredCircles,
              count: 20,
              followsLists: _filteredFollowsLists))
          .posts;

      if (morePosts.length == 0) {
        _setLoadingFinished(true);
      } else {
        setState(() {
          _posts.addAll(morePosts);
          _posts.forEach((Post post) {
            _buildAndStorePostWidget(post);
          });
        });
      }
      return true;
    } on HttpieConnectionRefusedError catch (error) {
      _onConnectionRefusedError(error);
    } catch (error) {
      _onUnknownError(error);
      rethrow;
    }

    return false;
  }

  Widget _getWidgetForPost(Post post) {
    int cacheKey = post.id;

    Widget postWidget = _postsWidgetsCache.get(cacheKey);
    if (postWidget != null) return postWidget;
    return _buildAndStorePostWidget(post);
  }

  Widget _buildAndStorePostWidget(Post post) {
    int cacheKey = post.id;
    var postWidget = _buildPostWidget(post);
    _postsWidgetsCache.set(cacheKey, postWidget);
    return postWidget;
  }

  Widget _buildPostWidget(Post post) {
    return OBPost(
      post,
      onPostDeleted: _onPostDeleted,
      key: Key(
        post.id.toString(),
      ),
    );
  }

  void _onPostDeleted(Post deletedPost) {
    setState(() {
      _posts.remove(deletedPost);
    });
  }

  void _setPosts(List<Post> posts) {
    setState(() {
      _posts = posts;
      _posts.forEach((Post post) {
        _buildAndStorePostWidget(post);
      });
    });
  }

  void _setLoadingFinished(bool loadingFinished) {
    setState(() {
      _loadingFinished = loadingFinished;
    });
  }

  void _setRefreshInProgress(bool refreshInProgress) {
    setState(() {
      _refreshInProgress = refreshInProgress;
    });
  }

  void _onConnectionRefusedError(HttpieConnectionRefusedError error) {
    _toastService.error(message: 'No internet connection', context: context);
  }

  void _onUnknownError(Error error) {
    _toastService.error(message: 'Unknown error', context: context);
  }
}

class OBTimelinePostsController {
  OBTimelinePostsState _homePostsState;

  /// Register the OBHomePostsState to the controller
  void attach(OBTimelinePostsState homePostsState) {
    assert(homePostsState != null, 'Cannot attach to empty state');
    _homePostsState = homePostsState;
  }

  void addPostToTop(Post post) {
    _homePostsState.addPostToTop(post);
  }

  void scrollToTop() {
    _homePostsState.scrollToTop();
  }

  bool isAttached() {
    return _homePostsState != null;
  }

  Future<void> setFilters(
      {List<Circle> circles, List<FollowsList> followsLists}) async {
    return _homePostsState.setFilters(
        circles: circles, followsLists: followsLists);
  }

  Future<void> clearFilters() {
    return _homePostsState.clearFilters();
  }

  List<Circle> getFilteredCircles() {
    return _homePostsState.getFilteredCircles();
  }

  List<FollowsList> getFilteredFollowsLists() {
    return _homePostsState.getFilteredFollowsLists();
  }

  int countFilters() {
    return _homePostsState.getFilteredCircles().length +
        _homePostsState.getFilteredFollowsLists().length;
  }
}

class OBHomePostsLoadMoreDelegate extends LoadMoreDelegate {
  const OBHomePostsLoadMoreDelegate();

  @override
  Widget buildChild(LoadMoreStatus status,
      {LoadMoreTextBuilder builder = DefaultLoadMoreTextBuilder.english}) {
    String text = builder(status);

    if (status == LoadMoreStatus.fail) {
      return Container(
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.refresh),
            SizedBox(
              width: 10.0,
            ),
            Text('Tap to retry loading posts.')
          ],
        ),
      );
    }
    if (status == LoadMoreStatus.idle) {
      // No clue why is this even a state.
      return SizedBox();
    }
    if (status == LoadMoreStatus.loading) {
      return Container(
          child: Center(
        child: OBProgressIndicator(),
      ));
    }
    if (status == LoadMoreStatus.nomore) {
      return SizedBox();
    }

    return Text(text);
  }
}
