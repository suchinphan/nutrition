from PIL import Image
import sys
import os

def sample_background_color(img):
    w,h = img.size
    # sample 4 corners 10x10
    samples = []
    for x in range(0, min(10,w)):
        for y in range(0, min(10,h)):
            samples.append(img.getpixel((x,y)))
            samples.append(img.getpixel((w-1-x,y)))
            samples.append(img.getpixel((x,h-1-y)))
            samples.append(img.getpixel((w-1-x,h-1-y)))
    r = sum([c[0] for c in samples]) / len(samples)
    g = sum([c[1] for c in samples]) / len(samples)
    b = sum([c[2] for c in samples]) / len(samples)
    return (r,g,b)


def color_dist(c1,c2):
    return ((c1[0]-c2[0])**2 + (c1[1]-c2[1])**2 + (c1[2]-c2[2])**2) ** 0.5


def remove_bg(in_path, out_path, tolerance=60):
    img = Image.open(in_path).convert('RGBA')
    bg = sample_background_color(img.convert('RGB'))
    px = img.load()
    w,h = img.size
    for y in range(h):
        for x in range(w):
            r,g,b,a = px[x,y]
            d = color_dist((r,g,b), bg)
            # also allow near-gray backgrounds by brightness
            brightness = (r+g+b)/3
            if d < tolerance or brightness > 230:
                px[x,y] = (r,g,b,0)
    img.save(out_path)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('Usage: remove_bg.py input.jpg output.png')
        sys.exit(1)
    inp = sys.argv[1]
    out = sys.argv[2]
    if not os.path.exists(inp):
        print('Input file not found:', inp)
        sys.exit(2)
    try:
        remove_bg(inp,out)
        print('Saved', out)
    except Exception as e:
        print('Error:', e)
        sys.exit(3)
