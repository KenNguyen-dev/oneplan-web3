import { classifyActivity } from './activity-hints';
import { ImageGate, reviewImageTitle } from './image-relevance';
import {
  destinationRelevanceTokens,
  imageRelevanceTokens,
} from './place-lookup';

// Builds the gate the service builds, so the tests exercise the real wiring.
function gateFor(
  itemText: string,
  venue: string,
  destination = 'Cao Bằng, Cao Bằng, Vietnam',
): ImageGate {
  return {
    venueTokens: imageRelevanceTokens(venue),
    destTokens: destinationRelevanceTokens(destination),
    destination,
    activity: classifyActivity(itemText),
  };
}

const verdict = (title: string, gate: ImageGate) =>
  reviewImageTitle(title, gate).verdict;

describe('reviewImageTitle', () => {
  // The three failures from the Cao Bang listing (2026-07). Each one passed
  // the old any-token filter; none may pass again.
  describe('regressions from the Cao Bang listing', () => {
    const dinner = gateFor(
      'Bữa tối ấm cúng với đặc sản địa phương',
      'Nhà hàng Minh Nguyệt',
    );

    it('rejects a city landscape served as dinner', () => {
      expect(verdict('Thác Bản Giốc Cao Bằng đẹp nao lòng', dinner)).toBe(
        'fail',
      );
    });

    it('rejects a hotel lobby served as dinner', () => {
      expect(verdict('Khách sạn Cao Bằng giá rẻ trung tâm', dinner)).toBe(
        'fail',
      );
    });

    it('accepts a real photo of that restaurant', () => {
      expect(verdict('Nhà hàng Minh Nguyệt Cao Bằng', dinner)).toBe('pass');
    });

    it('accepts local food when the venue is not named', () => {
      expect(verdict('Đặc sản Cao Bằng: vịt quay 7 vị', dinner)).toBe('pass');
    });

    const cafe = gateFor('Cà phê chia tay tại La-Rose', 'La-Rose coffee & tea');

    it('rejects noodle bowls served as coffee', () => {
      expect(verdict('Phở chua Cao Bằng ngon nức tiếng', cafe)).toBe('fail');
      expect(verdict('Bánh cuốn canh Cao Bằng', cafe)).toBe('fail');
    });

    it('accepts a cafe photo', () => {
      expect(verdict('La Rose Coffee & Tea không gian đẹp', cafe)).toBe('pass');
      expect(verdict('Quán cafe view đẹp ở Cao Bằng', cafe)).toBe('pass');
    });

    const phoChua = gateFor(
      'Thưởng thức Phở chua Cao Bằng',
      'Phở chua Dung Trang',
    );

    it('rejects kitchen equipment matched on the syllable "trang"', () => {
      expect(verdict('Trang thiết bị bếp inox công nghiệp', phoChua)).toBe(
        'fail',
      );
    });

    it('accepts the dish itself', () => {
      expect(verdict('Phở chua Cao Bằng món ăn đặc sản', phoChua)).toBe('pass');
    });
  });

  describe('place gate', () => {
    const gate = gateFor('Ăn trưa', 'Nhà hàng Minh Nguyệt');

    it('needs two distinctive venue tokens, not one common syllable', () => {
      expect(verdict('Chị Minh bán hàng rong Hà Nội', gate)).toBe('fail');
      expect(verdict('Minh Nguyệt quán ngon', gate)).toBe('pass');
    });

    it('accepts a single-token venue only with city or activity context', () => {
      const single = gateFor('Cà phê sáng', 'Gió Coffee');
      expect(verdict('Gió lạnh đầu mùa', single)).toBe('fail');
      expect(verdict('Gió Coffee Cao Bằng', single)).toBe('pass');
    });

    it('rejects a photo with neither venue nor destination', () => {
      expect(verdict('Bún bò Huế ngon nhất Đà Nẵng', gate)).toBe('fail');
    });

    // The same venue name exists in several provinces, so the name alone is
    // not proof of place.
    it('rejects the same venue name in another province', () => {
      expect(verdict('Nhà Hàng Minh Nguyệt | Thái Nguyên', gate)).toBe('fail');
      expect(verdict('Nhà hàng Minh Nguyệt Cao Bằng', gate)).toBe('pass');
    });

    it('does not treat the destination itself as a conflict', () => {
      const hcm = gateFor('Ăn tối', 'Quán Ngon 138', 'Hồ Chí Minh, Vietnam');
      expect(verdict('Quán Ngon 138 Hồ Chí Minh món ngon', hcm)).toBe('pass');
    });
  });

  describe('universal junk filter', () => {
    const gate = gateFor('Ăn tối', 'Nhà hàng Minh Nguyệt');

    it.each([
      'Logo nhà hàng Minh Nguyệt vector',
      'Bản đồ du lịch Cao Bằng',
      'Cho thuê nhà hàng Minh Nguyệt Cao Bằng',
    ])('rejects %s', (title) => {
      expect(verdict(title, gate)).toBe('fail');
    });
  });

  describe('untitled results', () => {
    it('is unverified, not passed, when there is no title', () => {
      const gate = gateFor('Ăn tối', 'Nhà hàng Minh Nguyệt');
      expect(verdict('', gate)).toBe('unverified');
      expect(verdict('   ', gate)).toBe('unverified');
    });
  });
});
