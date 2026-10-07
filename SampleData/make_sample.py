"""
検証タブ用のサンプルデータを作るスクリプト（架空のデータ）。

- ネオアイムジャグラーEX の公表スペック（BIG/REG確率・機械割・獲得枚数）で1Gずつ抽選
- 店の設定配分が違う2パターンを作る
    sample-validation.csv          「高設定少なめ」(設定1〜6 = 40/25/15/10/6/4%)
    sample-validation-uniform.csv  「均等」(設定1〜6 = 各1/6)
  それぞれ *-answers.csv が各台の本当の設定
- 小役の払い出しのブレは、1Gあたり標準偏差 約3.2枚の正規分布で近似（実機の値ではない）
- 10台 × 30日 = 300件。途中は2000G時点、最終は閉店時
- 一部の行は差枚が空欄、一部の行は最終が空欄（未完了）
"""
import csv, datetime, numpy as np

B = np.array([273.1, 269.7, 269.7, 259.0, 259.0, 255.0])
R = np.array([439.8, 399.6, 331.0, 315.1, 255.0, 255.0])
RATE = np.array([97.0, 98.0, 99.5, 101.1, 103.3, 105.5])
BP, RP, BET = 252, 96, 3
SMALL_ROLE_SD = 3.2
CHECK = 2000
HEADER = ["日付", "台番", "途中G数", "途中BIG", "途中REG", "途中差枚", "最終G数", "最終BIG", "最終REG", "最終差枚"]


def make(prior, seed, data_path, answers_path):
    rng = np.random.default_rng(seed)
    rows, answers = [], []
    start = datetime.date(2026, 9, 1)

    for day in range(30):
        date = start + datetime.timedelta(days=day)
        for unit in range(101, 111):
            s = rng.choice(6, p=prior)
            total = int(rng.integers(3500, 8501))          # その日の総回転数
            pB, pR = 1 / B[s], 1 / R[s]
            base = BET * RATE[s] / 100 - BP * pB - RP * pR - BET
            u = rng.random(total)
            big = u < pB
            reg = (u >= pB) & (u < pB + pR)
            diff = np.cumsum(base + rng.normal(0, SMALL_ROLE_SD, total) + BP * big + RP * reg)

            c = CHECK - 1
            row = [date.isoformat(), unit, CHECK, int(big[:CHECK].sum()), int(reg[:CHECK].sum()),
                   int(round(diff[c])), total, int(big.sum()), int(reg.sum()), int(round(diff[-1]))]
            k = rng.random()
            if k < 0.10:                 # 差枚が分からない台
                row[5] = row[9] = ""
            elif k < 0.13:               # 最終をまだ入れていない台（未完了）
                row[6] = row[7] = row[8] = row[9] = ""
            rows.append(row)
            answers.append([date.isoformat(), unit, s + 1, RATE[s]])

    with open(data_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(HEADER)
        w.writerows(rows)

    with open(answers_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["日付", "台番", "本当の設定", "機械割"])
        w.writerows(answers)

    settings = np.array([a[2] for a in answers])
    print(f"{data_path}: {len(rows)}件  設定の内訳 {np.bincount(settings, minlength=7)[1:].tolist()}"
          f"  平均機械割 {RATE[settings - 1].mean():.1f}%")


make(np.array([.40, .25, .15, .10, .06, .04]), 20260901,
     "sample-validation.csv", "sample-validation-answers.csv")
make(np.ones(6) / 6, 20260902,
     "sample-validation-uniform.csv", "sample-validation-uniform-answers.csv")
