%%% @doc A set of non-overlapping intervals.
-module(ar_intervals).

-export([
	new/0,
	add/3,
	delete/3,
	cut/2,
	is_inside/2,
	sum/1,
	outerjoin/2,
	get_interval_by_nth_inner_number/2,
	to_etf/2,
	to_json/2,
	safe_from_etf/1,
	count/1,
	is_empty/1,
	take_largest/1,
	compact/2,
	inverse/1
]).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Public interface.
%%%===================================================================

%% @doc Create an empty set of intervals.
new() ->
	gb_sets:new().

%% @doc Add a new interval. Intervals are compacted - e.g., (2, 1) and (1, 0) are joined
%% into (2, 0). Also, if two intervals intersect each other, they are joined.
add(Intervals, End, Start) when End > Start ->
	Iter = gb_sets:iterator_from({Start - 1, Start - 1}, Intervals),
	add2(Iter, Intervals, End, Start).

%% @doc Remove the given interval from the set.
delete(Intervals, End, Start) ->
	Iter = gb_sets:iterator_from({Start - 1, Start - 1}, Intervals),
	delete2(Iter, Intervals, End, Start).

%% @doc Remove the interval above the given cut. If there is an interval containing
%% the cut, replace it with its part up to the cut.
cut(Intervals, Cut) ->
	case gb_sets:size(Intervals) of
		0 ->
			Intervals;
		_ ->
			case gb_sets:take_largest(Intervals) of
				{{_, Start}, UpdatedIntervals} when Start >= Cut ->
					cut(UpdatedIntervals, Cut);
				{{End, Start}, UpdatedIntervals} when End > Cut ->
					gb_sets:add_element({Cut, Start}, UpdatedIntervals);
				_ ->
					Intervals
			end
	end.

%% @doc Return true if the given number is inside one of the intervals, false otherwise.
%% The left bounds of the intervals are excluded from search, the right bounds are included.
is_inside(Intervals, Number) ->
	Iter = gb_sets:iterator_from({Number - 1, Number - 1}, Intervals),
	case gb_sets:next(Iter) of
		none ->
			false;
		{{Number, _Start}, _Iter} ->
			true;
		{{_End, Start}, _Iter} when Number > Start ->
			true;
		_ ->
			false
	end.

%% @doc Return the sum of the lenghts of the intervals.
sum(Intervals) ->
	gb_sets:fold(fun({End, Start}, Acc) -> Acc + End - Start end, 0, Intervals).

%% @doc Return a set of intervals containing the points from the second given set of
%% intervals and excluding the points from the first given set of intervals.
outerjoin(I1, I2) ->
	intersection(inverse(I1), I2).

%% @doc Return {start, n, end} where {start, end} is the interval from the set
%% containing the found point n, n >= start, n < end, and n is the Nth (starting from 0) point
%% contained in the set of intervals when counted starting from the smallest interval, including
%% the left bounds and excluding the right bounds.
%% Raises a none exception, if the set does not contain enough points to find N.
get_interval_by_nth_inner_number(Intervals, N) ->
	get_interval_by_nth_inner_number2(gb_sets:iterator(Intervals), N).

%% @doc Serialize the given set of intervals to a binary that can be converted back
%% to the original set of intervals via safe_from_etf/1. If the given limit is greater than
%% or equal to the number of intervals, serialize all the intervals. If the given limit
%% is smaller, include at most so many intervals in the output where the probability of
%% including an interval is proportional to the ratio between the limit and the number
%% of intervals.
to_etf(Intervals, Limit) ->
	serialize(Intervals, Limit, etf).

%% @doc Serialize the given set of intervals to a JSON list of objects {"end": "start"}.
%% If the given limit is greater tha or equal to the number of intervals, serialize all
%% the intervals. If the given limit is smaller, include at most so many intervals in
%% the output where the probability of including an interval is proportional to the ratio
%% between the limit and the number of intervals.
to_json(Intervals, Limit) ->
	serialize(Intervals, Limit, json).

%% @doc Convert the binary produced by to_etf/2 into the set of intervals.
%% Return {error, invalid} if the binary is not a valid ETF representation of the
%% non-overlapping intervals.
safe_from_etf(Binary) ->
	case catch from_etf(Binary) of
		{ok, Intervals} ->
			{ok, Intervals};
		_ ->
			{error, invalid}
	end.

%% @doc Return the number of intervals in the set.
count(Intervals) ->
	gb_sets:size(Intervals).

%% @doc Return true if the set of intervals is empty, false otherwise.
is_empty(Intervals) ->
	gb_sets:is_empty(Intervals).

%% @doc Return {Interval, Intervals2} when Interval is the interval with the largest
%% right bound and Intervals2 is the set of intervals with this interval removed.
take_largest(Intervals) ->
	gb_sets:take_largest(Intervals).

%% @doc Join the neighboring intervals so that the number of intervals is equal to Limit.
%% The intervals with the smallest distance apart from each other are joined first.
%% Return {Compacted, Intervals2} where Compacted is the list of freshly included intervals,
%% Intervals2 is the new set of Limit intervals. If the set contains less intervals than
%% Limit, return {[], Intervals}.
compact(Intervals, Limit) when Limit > 0 ->
	Excess = count(Intervals) - Limit,
	case Excess =< 0 of
		true ->
			{[], Intervals};
		false ->
			{{infinity, _End}, I} =
				gb_sets:take_largest(inverse(Intervals)),
			I2 =
				case gb_sets:is_empty(I) of
					true ->
						I;
					false ->
						case gb_sets:take_smallest(I) of
							{{_, 0}, I3} ->
								I3;
							_ ->
								I
						end
				end,
			L = gb_sets:to_list(I2),
			Sorted =
				lists:sort(
					fun({End1, Start1}, {End2, Start2}) ->
						End1 - Start1 =< End2 - Start2
					end,
					L
				),
			lists:foldl(
				fun({End, Start}, {Compacted, Joined}) ->
					{[{End, Start} | Compacted], add(Joined, End, Start)}
				end,
				{[], Intervals},
				lists:sublist(Sorted, Excess)
			)
	end.

%%%===================================================================
%%% Private functions.
%%%===================================================================

add2(Iter, Intervals, End, Start) ->
	case gb_sets:next(Iter) of
		none ->
			gb_sets:add_element({End, Start}, Intervals);
		{{End2, Start2}, Iter2} when End >= Start2 andalso Start =< End2 ->
			End3 = max(End, End2),
			Start3 = min(Start, Start2),
			add2(Iter2, gb_sets:del_element({End2, Start2}, Intervals), End3, Start3);
		_ ->
			gb_sets:add_element({End, Start}, Intervals)
	end.

delete2(Iter, Intervals, End, Start) ->
	case gb_sets:next(Iter) of
		none ->
			Intervals;
		{{End2, Start2}, Iter2} when End >= Start2 andalso Start =< End2 ->
			Intervals2 = gb_sets:del_element({End2, Start2}, Intervals),
			Intervals3 =
				case End2 > End of
					true ->
						gb_sets:insert({End2, End}, Intervals2);
					false ->
						Intervals2
				end,
			Intervals4 =
				case Start > Start2 of
					true ->
						gb_sets:insert({Start, Start2}, Intervals3);
					false ->
						Intervals3
				end,
			delete2(Iter2, Intervals4, End, Start);
		_ ->
			Intervals
	end.

inverse(Intervals) ->
	inverse(gb_sets:iterator(Intervals), 0, new()).

inverse(Iterator, L, G) ->
	case gb_sets:next(Iterator) of
		none ->
			gb_sets:add_element({infinity, L}, G);
		{{End1, Start1}, I1} ->
			G2 = case Start1 > L of true -> gb_sets:add_element({Start1, L}, G); _ -> G end,
			L2 = End1,
			case gb_sets:next(I1) of
				none ->
					gb_sets:add_element({infinity, L2}, G2);
				{{End2, Start2}, I2} ->
					inverse(I2, End2, gb_sets:add_element({Start2, End1}, G2))
			end
	end.

intersection(I1, I2) ->
	intersection(gb_sets:iterator(I1), gb_sets:iterator(I2), new()).

intersection(I1, I2, G) ->
	case {gb_sets:next(I1), gb_sets:next(I2)} of
		{none, _} ->
			G;
		{_, none} ->
			G;
		{{{End1, _Start1}, UpdatedI1}, {{_End2, Start2}, _UpdatedI2}} when Start2 >= End1 ->
			intersection(UpdatedI1, I2, G);
		{{{_End1, Start1}, _UpdatedI1}, {{End2, _Start2}, UpdatedI2}} when Start1 >= End2 ->
			intersection(I1, UpdatedI2, G);
		{{{End1, Start1}, UpdatedI1}, {{End2, Start2}, _UpdatedI2}} when End2 >= End1 ->
			intersection(UpdatedI1, I2, gb_sets:add_element({End1, max(Start1, Start2)}, G));
		{{{End1, Start1}, _UpdatedI1}, {{End2, Start2}, UpdatedI2}} when End1 > End2 ->
			intersection(I1, UpdatedI2, gb_sets:add_element({End2, max(Start1, Start2)}, G))
	end.

get_interval_by_nth_inner_number2(Iterator, N) ->
	case gb_sets:next(Iterator) of
		none ->
			error(none);
		{{End, Start}, UpdatedIterator} when N >= End - Start ->
			get_interval_by_nth_inner_number2(UpdatedIterator, N - End + Start);
		{{End, Start}, _UpdatedIterator} ->
			{Start, Start + N, End}
	end.

serialize(Intervals, Limit, Format) ->
	case gb_sets:is_empty(Intervals) of
		true ->
			serialize_empty(Format);
		false ->
			Iterator = gb_sets:iterator(Intervals),
			serialize(Iterator, min(Limit / gb_sets:size(Intervals), 1), [], 0, Limit, Format)
	end.

serialize_empty(etf) ->
	term_to_binary([]);
serialize_empty(json) ->
	jiffy:encode([]).

serialize(_Iterator, _Probability, L, Count, Limit, Format) when Count == Limit ->
	serialize_list(L, Format);
serialize(Iterator, Probability, L, Count, Limit, Format) ->
	case gb_sets:next(Iterator) of
		none ->
			serialize_list(L, Format);
		{{End, Start}, UpdatedIterator} ->
			PickItem = case Probability < 1 of
				true ->
					rand:uniform() < Probability;
				false ->
					true
			end,
			case PickItem of
				false ->
					serialize(UpdatedIterator, Probability, L, Count, Limit, Format);
				true ->
					UpdatedL = [serialize_item(End, Start, Format) | L],
					serialize(UpdatedIterator, Probability, UpdatedL, Count + 1, Limit, Format)
			end
	end.

serialize_list(L, etf) ->
	term_to_binary(L);
serialize_list(L, json) ->
	jiffy:encode(L).

serialize_item(End, Start, etf) ->
	{<< End:256 >>, << Start:256 >>};
serialize_item(End, Start, json) ->
	#{ integer_to_binary(End) => integer_to_binary(Start) }.

from_etf(Binary) ->
	L = binary_to_term(Binary, [safe]),
	from_etf(L, infinity, new()).

from_etf([], _, Intervals) ->
	{ok, Intervals};
from_etf([{<< End:256 >>, << Start:256 >>} | List], R, Intervals)
		when End > Start andalso R > End andalso Start >= 0 ->
	from_etf(List, Start, gb_sets:add_element({End, Start}, Intervals)).

%%%===================================================================
%%% Tests.
%%%===================================================================

intervals_test() ->
	I = new(),
	?assertEqual(0, count(I)),
	?assertEqual(0, sum(I)),
	?assert(not is_inside(I, 0)),
	?assert(not is_inside(I, 1)),
	?assertEqual(new(), outerjoin(I, I)),
	?assertEqual(<<"[]">>, to_json(I, 1)),
	?assertEqual({ok, new()}, safe_from_etf(to_etf(I, 1))),
	?assertEqual(new(), outerjoin(I, I)),
	?assertEqual(new(), delete(I, 2, 1)),
	?assertException(error, none, get_interval_by_nth_inner_number(I, 0)),
	?assertException(error, none, get_interval_by_nth_inner_number(I, 2)),
	{[], CI} = compact(I, 1),
	?assertEqual(new(), CI),
	I2 = add(I, 2, 1),
	?assertEqual(1, count(I2)),
	?assertEqual(1, sum(I2)),
	?assert(not is_inside(I2, 0)),
	?assert(not is_inside(I2, 1)),
	?assert(is_inside(I2, 2)),
	?assert(not is_inside(I2, 3)),
	?assertEqual({1, 1, 2}, get_interval_by_nth_inner_number(I2, 0)),
	?assertException(error, none, get_interval_by_nth_inner_number(I2, 1)),
	?assertEqual(new(), outerjoin(I2, I)),
	compare(add(add(new(), 1, 0), 3, 2), outerjoin(I2, add(new(), 3, 0))),
	?assertEqual(new(), delete(I2, 2, 1)),
	?assertEqual(new(), delete(I2, 2, 0)),
	?assertEqual(new(), delete(I2, 3, 1)),
	?assertEqual(new(), delete(I2, 3, 0)),
	?assertEqual(new(), cut(I2, 1)),
	?assertEqual(new(), cut(I2, 0)),
	compare(I2, cut(I2, 2)),
	compare(I2, cut(I2, 3)),
	?assertEqual(<<"[{\"2\":\"1\"}]">>, to_json(I2, 1)),
	?assertEqual(<<"[]">>, to_json(I2, 0)),
	{[], CI2_2} = compact(I2, 2),
	compare(I2, CI2_2),
	{ok, I2_FromETF} = safe_from_etf(to_etf(I2, 1)),
	compare(I2, I2_FromETF),
	?assertEqual({ok, new()}, safe_from_etf(to_etf(I2, 0))),
	compare(I2, add(I2, 2, 1)),
	compare(add(new(), 3, 1), add(I2, 3, 1)),
	compare(add(new(), 2, 0), add(I2, 2, 0)),
	I3 = add(I2, 6, 3),
	?assertEqual(2, count(I3)),
	?assertEqual(4, sum(I3)),
	?assert(not is_inside(I3, 0)),
	?assert(not is_inside(I3, 1)),
	?assert(is_inside(I3, 2)),
	?assert(not is_inside(I3, 3)),
	?assert(is_inside(I3, 4)),
	?assert(is_inside(I3, 5)),
	?assert(is_inside(I3, 6)),
	?assertEqual({1, 1, 2}, get_interval_by_nth_inner_number(I3, 0)),
	?assertEqual({3, 3, 6}, get_interval_by_nth_inner_number(I3, 1)),
	?assertEqual({3, 4, 6}, get_interval_by_nth_inner_number(I3, 2)),
	?assertEqual({3, 5, 6}, get_interval_by_nth_inner_number(I3, 3)),
	?assertException(error, none, get_interval_by_nth_inner_number(I3, 4)),
	{[], CI3} = compact(I3, 2),
	compare(I3, CI3),
	{[{3, 2}], CI3_2} = compact(I3, 1),
	compare(add(new(), 6, 1), CI3_2),
	I3_2 = add(new(), 7, 5),
	compare(add(new(), 7, 5), outerjoin(I2, I3_2)),
	compare(add(new(), 7, 6), outerjoin(I3, I3_2)),
	compare(add(add(add(new(), 1, 0), 3, 2), 8, 6), outerjoin(I3, add(new(), 8, 0))),
	compare(add(add(add(new(), 2, 1), 6, 5), 4, 3), delete(I3, 5, 4)),
	compare(add(new(), 6, 5), delete(I3, 5, 1)),
	compare(add(new(), 10, 0), add(I3, 10, 0)),
	?assertEqual(new(), cut(I3, 1)),
	?assertEqual(new(), cut(I3, 0)),
	?assertEqual(I2, cut(I3, 2)),
	?assertEqual(I2, cut(I3, 3)),
	compare(add(I2, 4, 3), cut(I3, 4)),
	compare(add(I2, 5, 3), cut(I3, 5)),
	compare(I3, cut(I3, 6)),
	?assertEqual(<<"[{\"6\":\"3\"},{\"2\":\"1\"}]">>, to_json(I3, 10)),
	{ok, I3_FromETF} = safe_from_etf(to_etf(I3, 10)),
	compare(I3, I3_FromETF),
	compare(I3, add(I3, 4, 3)),
	compare(add(new(), 6, 1), add(I3, 3, 1)),
	I4 = add(I3, 7, 6),
	?assertEqual(2, count(I4)),
	?assertEqual(5, sum(I4)),
	?assert(not is_inside(I4, 0)),
	?assert(not is_inside(I4, 1)),
	?assert(is_inside(I4, 2)),
	?assert(not is_inside(I4, 3)),
	?assert(is_inside(I4, 4)),
	?assert(is_inside(I4, 5)),
	?assert(is_inside(I4, 6)),
	?assert(is_inside(I4, 7)),
	?assert(not is_inside(I4, 8)),
	?assertEqual({1, 1, 2}, get_interval_by_nth_inner_number(I4, 0)),
	?assertEqual({3, 3, 7}, get_interval_by_nth_inner_number(I4, 1)),
	?assertEqual({3, 6, 7}, get_interval_by_nth_inner_number(I4, 4)),
	compare(add(add(new(), 1, 0), 3, 2), outerjoin(I4, add(new(), 6, 0))),
	?assertEqual(new(), cut(I4, 1)),
	?assertEqual(new(), cut(I4, 0)),
	compare(add(I2, 5, 3), cut(I4, 5)),
	compare(I4, cut(I4, 7)),
	{[], CI4} = compact(I4, 2),
	compare(I4, CI4),
	{[{3, 2}], CI4_2} = compact(I4, 1),
	compare(add(new(), 7, 1), CI4_2),
	?assertEqual(<<"[{\"7\":\"3\"},{\"2\":\"1\"}]">>, to_json(I4, 10)),
	{ok, I4_FromETF} = safe_from_etf(to_etf(I4, count(I4))),
	compare(I4, I4_FromETF),
	I5 = add(I4, 3, 2),
	?assertEqual(1, count(I5)),
	?assertEqual(6, sum(I5)),
	compare(I5, add(I5, 3, 2)),
	compare(I5, add(I5, 2, 1)),
	compare(add(new(), 8, 1), add(I5, 8, 6)),
	{[{9, 2}], C} = compact(add(add(new(), 2, 0), 10, 9), 1),
	compare(add(new(), 10, 0), C),
	I6 = add(add(add(add(new(), 3, 1), 12, 8), 25, 22), 27, 26),
	{[], CI6} = compact(I6, 10),
	compare(I6, CI6),
	{[], CI6_2} = compact(I6, 4),
	compare(I6, CI6_2),
	{[{26, 25}], CI6_3} = compact(I6, 3),
	compare(add(add(add(new(), 3, 1), 12, 8), 27, 22), CI6_3),
	{[{8, 3}, {26, 25}], CI6_4} = compact(I6, 2),
	compare(add(add(new(), 12, 1), 27, 22), CI6_4),
	{[{22, 12}, {8, 3}, {26, 25}], CI6_5} = compact(I6, 1),
	compare(add(new(), 27, 1), CI6_5),
	I8 = add(add(new(), 5, 3), 10, 9),
	{[{9, 5}], I8_2} = compact(I8, 1),
	compare(add(new(), 10, 3), I8_2),
	compare(add(add(new(), 3, 2), 8, 7), delete(add(add(new(), 4, 2), 8, 6), 7, 3)).

compare(I1, I2) ->
	?assertEqual(to_json(I1, count(I1)), to_json(I2, count(I2))),
	Folded1 = gb_sets:fold(fun({K, V}, Acc) -> [{K, V} | Acc] end, [], I1),
	Folded2 = gb_sets:fold(fun({K, V}, Acc) -> [{K, V} | Acc] end, [], I2),
	?assertEqual(Folded1, Folded2).
