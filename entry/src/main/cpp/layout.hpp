//
// Created on 2025/10/26.
//
// Node APIs are not fully supported. To solve the compilation error of the interface cannot be found,
// please include "napi/native_api.h".

#ifndef EASYTIER_LAYOUT_H
#define EASYTIER_LAYOUT_H
#include <iostream>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <string>
using namespace std;

struct Rect {
    string id;
    float x, y, w, h;
    Rect() : id(""), x(0), y(0), w(0), h(0) {}
    Rect(string id, float w, float h, float x=0, float y=0)
        : id(move(id)), x(x), y(y), w(w), h(h) {}

    bool intersects(const Rect &o) const {
        return !(x + w <= o.x || o.x + o.w <= x ||
                 y + h <= o.y || o.y + o.h <= y);
    }
};

struct RectState {
    string id;
    float w, h;
};

struct Layout {
    float width, height;
    unordered_map<string, Rect> rects;
    vector<string> order; // 添加顺序

    Layout(float w, float h) : width(w), height(h) {}

    bool findEmptySpot(float w, float h, float &ox, float &oy) {
        const float step = 1;
        for(float y=0; y+h<=height; y+=step){
            for(float x=0; x+w<=width; x+=step){
                Rect test("", w,h,x,y);
                bool collide=false;
                for(auto &[_, r]: rects) if(r.intersects(test)){ collide=true; break; }
                if(!collide){ ox=x; oy=y; return true; }
            }
        }
        return false;
    }

    void add(string id, float w, float h){
        if(rects.count(id)){ cout<<"⚠️ 已存在: "<<id<<"\n"; return; }
        float x=0,y=0;
        if(!findEmptySpot(w,h,x,y)){ cout<<"❌ 无空位添加组件 "<<id<<"\n"; return; }
        rects[id]=Rect(id,w,h,x,y);
        order.push_back(id);
        cout<<"✅ 添加 "<<id<<" @("<<x<<","<<y<<")\n";
        refillGaps(); // 回填其他组件
    }

    void move(string id, float newX, float newY){
        if(!rects.count(id)){ cout<<"❌ 未找到: "<<id<<"\n"; return; }
        Rect &r = rects[id];
        Rect newR(r.id,r.w,r.h,newX,newY);

        // 检查碰撞
        for(auto &[oid, other]: rects){
            if(oid==id) continue;
            if(newR.intersects(other)) cout<<"⚠️ 移动后会与 "<<oid<<" 冲突\n";
        }

        r.x = newX; r.y = newY;
        cout<<"➡️ 移动 "<<id<<" -> ("<<newX<<","<<newY<<")\n";
        refillGaps({id});
    }

    void remove(string id){
        if(!rects.count(id)){ cout<<"❌ 未找到: "<<id<<"\n"; return; }
        rects.erase(id);
        auto it = find(order.begin(), order.end(), id);
        if(it != order.end()) order.erase(it);
        cout<<"🗑️ 删除 "<<id<<"\n";
        refillGaps();
    }

    bool resize(const string &id, const string &direction, float offset){
        if(!rects.count(id)){ cout<<"❌ 未找到: "<<id<<"\n"; return false; }
        Rect old = rects[id];
        Rect r = old;

        if(direction=="right") r.w += offset;
        else if(direction=="left"){ r.x-=offset; r.w+=offset; }
        else if(direction=="down") r.h+=offset;
        else if(direction=="up"){ r.y-=offset; r.h+=offset; }
        else { cout<<"❌ 无效方向\n"; return false; }

        if(r.w<=0 || r.h<=0){ cout<<"❌ 尺寸无效\n"; return false; }
        if(r.x<0 || r.y<0 || r.x+r.w>width || r.y+r.h>height){
            cout<<"🔧 调整 "<<id<<" 向"<<direction<<" 扩展 "<<offset<<"\n";
            cout<<"❌ 超出布局范围\n"; return false;
        }

        for(auto &[oid, other]: rects){
            if(oid==id) continue;
            if(r.intersects(other)){
                cout<<"🔧 调整 "<<id<<" 向"<<direction<<" 扩展 "<<offset<<"\n";
                cout<<"⚠️ 调整后会与 "<<oid<<" 冲突\n";
                return false;
            }
        }

        rects[id] = r;
        cout<<"🔧 调整 "<<id<<" 向"<<direction<<" 扩展 "<<offset<<"\n";
        refillGaps();
        return true;
    }

    // 回填未被excludeIds占用的组件
    void refillGaps(const vector<string> &excludeIds = {}){
        float cx=0, cy=0, rowH=0;
        for(const auto &id: order){
            if(find(excludeIds.begin(), excludeIds.end(), id) != excludeIds.end()) continue;
            Rect &r = rects[id];
            if(cx + r.w > width){ cx=0; cy+=rowH; rowH=0; }
            r.x=cx; r.y=cy;
            cx += r.w;
            rowH = max(rowH, r.h);
        }
    }

    void print() const {
        int W=(int)width,H=(int)height;
        vector<string> canvas(H,string(W,'.'));
        for(auto &[id,r]: rects){
            char ch = id.empty()?'?':toupper(id[0]);
            for(int yy=(int)r.y; yy<min(H,(int)(r.y+r.h)); yy++)
                for(int xx=(int)r.x; xx<min(W,(int)(r.x+r.w)); xx++)
                    canvas[yy][xx]=ch;
        }
        cout<<"=== Layout View ===\n";
        for(int yy=0; yy<H; yy++) cout<<canvas[yy]<<"\n";
        cout<<"===================\n";
    }

    vector<RectState> exportState() const {
        vector<RectState> state;
        for(const auto &id: order){
            const Rect &r = rects.at(id);
            state.push_back({id,r.w,r.h});
        }
        return state;
    }

    void importState(const vector<RectState> &state){
        rects.clear(); order.clear();
        for(const auto &s: state){
            float x=0,y=0;
            if(!findEmptySpot(s.w,s.h,x,y)){
                cout<<"❌ 无法放置组件 "<<s.id<<"\n";
                continue;
            }
            rects[s.id]=Rect(s.id,s.w,s.h,x,y);
            order.push_back(s.id);
        }
    }
};
#endif //EASYTIER_LAYOUT_H
