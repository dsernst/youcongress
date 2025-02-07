defmodule YouCongressWeb.VotingLiveTest do
  use YouCongressWeb.ConnCase

  import Mock

  import Phoenix.LiveViewTest
  import YouCongress.VotingsFixtures

  alias YouCongress.AccountsFixtures
  alias YouCongress.VotesFixtures
  alias YouCongress.OpinionsFixtures
  alias YouCongress.Votings

  @create_attrs %{title: "nuclear energy"}
  @suggested_titles [
    "Should we increase investment in nuclear energy research?",
    "Shall we consider nuclear energy as a viable alternative to fossil fuels?",
    "Could nuclear energy be a key solution for reducing global carbon emissions?"
  ]
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  defp create_voting(_) do
    voting = voting_fixture()
    %{voting: voting}
  end

  describe "Index" do
    setup [:create_voting]

    test "lists all votings", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)
      {:ok, _index_live, html} = live(conn, ~p"/halls")

      assert html =~ "YouCongress: Public Opinion Polls with AI and Delegation"
      assert html =~ voting.title
    end

    test "saves new voting and redirect to show", %{conn: conn} do
      with_mocks([
        {YouCongress.Votings.TitleRewording, [],
         [generate_rewordings: fn _, _ -> {:ok, @suggested_titles, 0} end]},
        {Oban, [], [insert: fn _ -> {:ok, %{id: 1}} end]}
      ]) do
        conn = log_in_as_admin(conn)
        {:ok, index_live, _html} = live(conn, ~p"/halls")

        index_live
        |> element("button", "Create poll")
        |> render_click()

        assert index_live
               |> form("#voting-form", voting: @invalid_attrs)
               |> render_change() =~ "can&#39;t be blank"

        [title1, title2, _title3] = @suggested_titles

        assert index_live
               |> form("#voting-form", voting: @create_attrs)
               |> render_submit() =~ title1

        response =
          index_live
          |> element("button", title2)
          |> render_click()

        voting = Votings.get_voting!(%{title: title2})
        voting_path = ~p"/v/#{voting.slug}"

        {_, {:redirect, %{to: ^voting_path}}} = response
      end
    end
  end

  describe "Show" do
    setup [:create_voting]

    test "displays voting as logged user", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      {:ok, _show_live, html} = live(conn, ~p"/v/#{voting.slug}")

      assert html =~ voting.title
    end

    # test "displays voting as non-logged visitor", %{conn: conn, voting: voting} do
    #   {:ok, _show_live, html} = live(conn, ~p"/v/#{voting.slug}")

    #   assert html =~ "Show Voting"
    #   assert html =~ voting.title
    # end

    test "updates voting within modal", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, show_live, _html} = live(conn, ~p"/v/#{voting.slug}")

      assert show_live
             |> element("a", "Edit")
             |> render_click() =~ "Edit Voting"

      assert_patch(show_live, ~p"/v/#{voting.slug}/show/edit")

      assert show_live
             |> form("#voting-form", voting: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#voting-form", voting: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/v/#{voting.slug}")

      html = render(show_live)
      assert html =~ "Voting updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes voting in listing", %{conn: conn, voting: voting} do
      conn = log_in_as_admin(conn)

      {:ok, index_live, _html} = live(conn, ~p"/v/#{voting.slug}/edit")

      index_live
      |> element("a", "Delete")
      |> render_click()

      assert_raise Ecto.NoResultsError, fn ->
        Votings.get_voting!(voting.id)
      end
    end

    test "casts a vote from voting buttons", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      opinion = OpinionsFixtures.opinion_fixture(%{voting_id: voting.id})
      #  Create a vote so we display the voting options
      VotesFixtures.vote_fixture(%{voting_id: voting.id, opinion_id: opinion.id})

      {:ok, show_live, _html} = live(conn, ~p"/v/#{voting.slug}")

      #  Vote strongly agree
      show_live
      |> element("button#mobile-vote-strongly-agree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Strongly agree"

      # Vote agree
      show_live
      |> element("button#mobile-vote-agree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Agree"

      # Vote Abstain
      show_live
      |> element("button#mobile-vote-abstain")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Abstain"

      # Vote N/A
      show_live
      |> element("button#mobile-vote-na")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted N/A"

      # Vote disagree
      show_live
      |> element("button#mobile-vote-disagree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Disagree"

      # Vote strongly disagree
      show_live
      |> element("button#mobile-vote-strongly-disagree")
      |> render_click()

      html = render(show_live)
      assert html =~ "You voted Strongly disagree"
    end

    test "creates a comment", %{conn: conn, voting: voting} do
      conn = log_in_as_user(conn)

      another_user = AccountsFixtures.user_fixture()

      opinion = OpinionsFixtures.opinion_fixture(%{voting_id: voting.id})

      #  Create an AI generated comment as we don't display the form until we have one of these
      VotesFixtures.vote_fixture(%{
        twin: true,
        voting_id: voting.id,
        author_id: another_user.author_id,
        opinion_id: opinion.id
      })

      {:ok, show_live, _html} = live(conn, ~p"/v/#{voting.slug}")

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Comment created successfully"
      assert html =~ "some comment"

      # Check that the vote is N/A
      assert html =~ "N/A"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end

    test "edit a comment", %{conn: conn, voting: voting} do
      user = AccountsFixtures.user_fixture()

      conn = log_in_user(conn, user)

      opinion =
        OpinionsFixtures.opinion_fixture(%{
          author_id: user.author_id,
          user_id: user.id,
          voting_id: voting.id,
          content: "whatever",
          twin: false
        })

      VotesFixtures.vote_fixture(%{
        voting_id: voting.id,
        author_id: user.author_id,
        opinion_id: opinion.id,
        user_id: user.id,
        twin: false
      })

      #  Create an AI generated comment as we don't display the form until we have one of these
      VotesFixtures.vote_fixture(%{twin: true, voting_id: voting.id}, true)

      {:ok, show_live, _html} = live(conn, ~p"/v/#{voting.slug}")

      assert render(show_live) =~ "whatever"

      show_live
      |> element("a", "Edit comment")
      |> render_click()

      show_live
      |> form("#comment-form", comment: "some comment")
      |> render_submit()

      html = render(show_live)
      assert html =~ "Your comment has been updated"
      refute html =~ "whatever"
      assert html =~ "some comment"

      # Check that there is non- AI-generated comment
      assert html =~ "and says"
    end
  end
end
