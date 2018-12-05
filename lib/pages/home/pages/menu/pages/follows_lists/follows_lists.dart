import 'package:Openbook/models/follows_list.dart';
import 'package:Openbook/models/user.dart';
import 'package:Openbook/pages/home/pages/menu/pages/follows_lists/widgets/follows_list_tile.dart';
import 'package:Openbook/pages/home/pages/menu/widgets/menu_nav_bar.dart';
import 'package:Openbook/widgets/icon.dart';
import 'package:Openbook/widgets/page_scaffold.dart';
import 'package:Openbook/pages/home/pages/profile/profile.dart';
import 'package:Openbook/provider.dart';
import 'package:Openbook/services/toast.dart';
import 'package:Openbook/services/user.dart';
import 'package:Openbook/widgets/routes/slide_right_route.dart';
import 'package:Openbook/widgets/search_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:Openbook/services/httpie.dart';

class OBFollowsListsPage extends StatefulWidget {
  final OnWantsToCreateFollowsList onWantsToCreateFollowsList;
  final OnWantsToSeeFollowsList onWantsToSeeFollowsList;

  OBFollowsListsPage(
      {this.onWantsToCreateFollowsList, this.onWantsToSeeFollowsList});

  @override
  State<OBFollowsListsPage> createState() {
    return OBFollowsListsPageState();
  }
}

class OBFollowsListsPageState extends State<OBFollowsListsPage> {
  UserService _userService;
  ToastService _toastService;

  GlobalKey<RefreshIndicatorState> _refreshIndicatorKey;
  ScrollController _followsListsScrollController;
  List<FollowsList> _followsLists = [];
  List<FollowsList> _followsListsSearchResults = [];

  bool _isEditing;
  bool _needsBootstrap;

  @override
  void initState() {
    super.initState();
    _followsListsScrollController = ScrollController();
    _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();
    _needsBootstrap = true;
    _isEditing = false;
    _followsLists = [];
  }

  @override
  Widget build(BuildContext context) {
    var provider = OpenbookProvider.of(context);
    _userService = provider.userService;
    _toastService = provider.toastService;

    if (_needsBootstrap) {
      _bootstrap();
      _needsBootstrap = false;
    }

    return OBCupertinoPageScaffold(
        backgroundColor: Color.fromARGB(0, 0, 0, 0),
        navigationBar: OBMenuNavBar(
          middle: Text('My lists'),
          trailing: GestureDetector(
            onTap: _toggleEdit,
            child: GestureDetector(
              child: Text(_isEditing ? 'Done' : 'Edit'),
              onTap: _toggleEdit,
            ),
          ),
        ),
        child: Stack(
          children: <Widget>[
            Container(
              color: Colors.white,
              child: Container(
                child: Column(
                  children: <Widget>[
                    Container(
                        child: OBSearchBar(
                      onSearch: _onSearch,
                      hintText: 'Search for a list...',
                    )),
                    Expanded(
                      child: RefreshIndicator(
                          key: _refreshIndicatorKey,
                          child: ListView.builder(
                              physics: AlwaysScrollableScrollPhysics(),
                              controller: _followsListsScrollController,
                              padding: EdgeInsets.all(0),
                              itemCount: _followsListsSearchResults.length,
                              itemBuilder: (context, index) {
                                int commentIndex = index;

                                var followsList =
                                    _followsListsSearchResults[commentIndex];

                                var onFollowsListDeletedCallback = () {
                                  _removeFollowsList(followsList);
                                };

                                return OBFollowsListTile(
                                  isEditing: _isEditing,
                                  followsList: followsList,
                                  onLongPress: _toggleEdit,
                                  onWantsToSeeFollowsList:
                                      widget.onWantsToSeeFollowsList,
                                  onFollowsListDeletedCallback:
                                      onFollowsListDeletedCallback,
                                );
                              }),
                          onRefresh: _refreshComments),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
                bottom: 20.0,
                right: 20.0,
                child: FloatingActionButton(
                    heroTag: Key('createFollowsListButton'),
                    backgroundColor: Colors.white,
                    onPressed: () async {
                      FollowsList createdFollowsList =
                          await widget.onWantsToCreateFollowsList();
                      if (createdFollowsList != null) {
                        _onFollowsListCreated(createdFollowsList);
                      }
                    },
                    child: OBIcon(OBIcons.createPost)))
          ],
        ));
  }

  void scrollToTop() {}

  void _bootstrap() async {
    await _refreshComments();
  }

  void _onWantsToSeeUserProfile(User user) {
    Navigator.push(
        context,
        OBSlideRightRoute(
            key: Key('obSlideProfileViewFromFollowsLists'),
            widget: OBProfilePage(user)));
  }

  void _toggleEdit() {
    _setIsEditing(!_isEditing);
  }

  Future<void> _refreshComments() async {
    try {
      _followsLists = (await _userService.getFollowsLists()).lists;
      _setFollowsLists(_followsLists);
      _scrollToTop();
    } on HttpieConnectionRefusedError catch (error) {
      _toastService.error(message: 'No internet connection', context: context);
    } catch (error) {
      _toastService.error(message: 'Unknown error', context: context);
      rethrow;
    }
  }

  void _onSearch(String query) {
    if (query.isEmpty) {
      _resetFollowsListsSearchResults();
      return;
    }

    String uppercaseQuery = query.toUpperCase();
    var searchResults = _followsLists.where((followsList) {
      return followsList.name.toUpperCase().contains(uppercaseQuery);
    }).toList();

    _setFollowsListsSearchResults(searchResults);
  }

  void _resetFollowsListsSearchResults() {
    _setFollowsListsSearchResults(_followsLists.toList());
  }

  void _setFollowsListsSearchResults(
      List<FollowsList> followsListsSearchResults) {
    setState(() {
      _followsListsSearchResults = followsListsSearchResults;
    });
  }

  void _removeFollowsList(FollowsList followsList) {
    setState(() {
      _followsLists.remove(followsList);
      _followsListsSearchResults.remove(followsList);
    });
  }

  void _onFollowsListCreated(FollowsList createdFollowsList) {
    setState(() {
      this._followsLists.insert(0, createdFollowsList);
      _scrollToTop();
    });
  }

  void _scrollToTop() {
    _followsListsScrollController.animateTo(
      0.0,
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _setFollowsLists(List<FollowsList> followsLists) {
    setState(() {
      this._followsLists = followsLists;
      _resetFollowsListsSearchResults();
    });
  }

  void _setIsEditing(bool isEditing) {
    setState(() {
      _isEditing = isEditing;
    });
  }
}

typedef Future<FollowsList> OnWantsToCreateFollowsList();
typedef void OnWantsToSeeFollowsList(FollowsList followsList);
