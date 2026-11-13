import 'package:flutter_test/flutter_test.dart';
import 'package:petory/domain/domain.dart';
import 'package:petory/l10n/ko.dart';

void main() {
  test('이/가는 받침 유무로 고른다', () {
    expect(Ko.iga('몽이'), '몽이가');
    expect(Ko.iga('콩'), '콩이');
    expect(Ko.iga('Mochi'), 'Mochi가');
  });
  test('으로/로는 받침과 ㄹ 받침을 구분한다', () {
    expect(Ko.euro('아기'), '아기로');
    expect(Ko.euro('성체'), '성체로');
    expect(Ko.euro('콩'), '콩으로');
    expect(Ko.euro('달'), '달로');
  });
  test('조사가 들어간 문구', () {
    expect(Ko.awayTitle('몽이'), '몽이가 기다렸어요');
    expect(Ko.awayTitle('콩'), '콩이 기다렸어요');
    expect(Ko.evolved('몽이', Stage.child), '몽이가 어린이로 자랐어요!');
  });
}
